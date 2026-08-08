import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';

/// One turn, streamed from an OpenAI-compatible server.
///
/// ## What this adapter is for
///
/// Our own server speaks a proprietary NDJSON event protocol and keeps the
/// conversation: the client sends one message and the server knows the rest.
/// A local runtime does neither — it speaks OpenAI SSE and is stateless, so
/// the full history has to travel with every request.
///
/// Rather than teach the UI a second protocol, this presents the OpenAI stream
/// as the same [StreamEvent] sequence the app already renders. The chat screen
/// cannot tell the difference, which is the point: one rendering path, not two
/// that drift.
///
/// ## What is deliberately missing
///
/// No tools. A local endpoint gets plain chat, because a 1–3B model driving a
/// shell on someone's phone is a different feature with different safety
/// questions, and pretending otherwise would produce tool calls nothing
/// executes. No server-side persistence either — the app already stores
/// messages locally, which is what makes the offline case work at all.
class LocalChatStream {
  const LocalChatStream._();

  /// Streams a completion from [baseUrl] for [messages].
  ///
  /// [messages] is the full conversation in OpenAI shape — `role` and
  /// `content` — oldest first, including the turn being answered.
  ///
  /// Yields the same events the server path does, so callers need no branch.
  static Stream<StreamEvent> send({
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration idleTimeout = const Duration(seconds: 120),
    HttpClient? client,
  }) async* {
    final http = client ?? HttpClient()
      ..connectionTimeout = connectTimeout;

    // A local id: nothing assigns one, and every downstream consumer keys on
    // it. Derived from the message count rather than a clock so the same
    // conversation replays identically in a test.
    final messageId = 'local-${model.hashCode.toUnsigned(16)}-${messages.length}';

    HttpClientResponse? res;
    try {
      final body = utf8.encode(jsonEncode({
        'model': model,
        'stream': true,
        'messages': [
          if (systemPrompt != null && systemPrompt.isNotEmpty)
            {'role': 'system', 'content': systemPrompt},
          ...messages,
        ],
      }));

      final req = await http
          .postUrl(Uri.parse('$baseUrl/v1/chat/completions'))
          .timeout(connectTimeout);
      req.headers.contentType = ContentType.json;
      // Content-Length, NOT chunked. Dart chunks the request body by default
      // when the length is unset, and the small C++ servers this talks to —
      // llama.cpp's included — parse that poorly or not at all. Measured
      // against a stub that read a chunked body as empty: the model answered
      // as though the conversation had no messages in it.
      req.contentLength = body.length;
      req.add(body);
      res = await req.close().timeout(connectTimeout);

      if (res.statusCode != 200) {
        final body = await res
            .transform(const Utf8Decoder(allowMalformed: true))
            .join()
            .timeout(connectTimeout);
        yield StreamEvent.error(
          message: _explain(res.statusCode, body, model),
          code: '${res.statusCode}',
        );
        return;
      }

      yield StreamEvent.start(messageId: messageId, model: model);

      var finish = 'stop';
      var sawContent = false;

      await for (final line in res
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .timeout(idleTimeout)) {
        final payload = _payloadOf(line);
        if (payload == null) continue;
        if (payload == '[DONE]') break;

        final chunk = _decodeChunk(payload);
        if (chunk == null) continue;
        if (chunk.finishReason != null) finish = chunk.finishReason!;
        if (chunk.content.isNotEmpty) {
          sawContent = true;
          yield StreamEvent.token(content: chunk.content);
        }
        if (chunk.usage != null) yield chunk.usage!;
      }

      // A stream that produced nothing is a failure the user can act on, not a
      // successful empty answer. Silently finishing would look like the model
      // ignoring them.
      if (!sawContent) {
        yield const StreamEvent.error(
          message: 'The local model returned nothing. It may still be loading '
              'the weights — try again in a moment.',
        );
        return;
      }

      yield StreamEvent.done(
        messageId: messageId,
        finishReason: finish,
        truncated: finish == 'length',
      );
    } on TimeoutException {
      yield const StreamEvent.error(
        message: 'The local model stopped responding. On a phone a large '
            'model can simply be too slow — try a smaller one.',
      );
    } on SocketException catch (e) {
      yield StreamEvent.error(
        message: 'Could not reach the local model: ${e.message}',
      );
    } on HttpException catch (e) {
      yield StreamEvent.error(message: 'Local model error: ${e.message}');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// Extracts the JSON from one SSE line, or null if it carries none.
  ///
  /// Handles both real SSE (`data: {...}`) and the bare NDJSON some runtimes
  /// emit when `stream: true` — llama-server has shipped both over time, and
  /// a parser that only knows one silently produces an empty answer.
  static String? _payloadOf(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('data:')) {
      final rest = trimmed.substring(5).trim();
      return rest.isEmpty ? null : rest;
    }
    // Comments and event/id fields carry nothing we need.
    if (trimmed.startsWith(':') ||
        trimmed.startsWith('event:') ||
        trimmed.startsWith('id:')) {
      return null;
    }
    return trimmed.startsWith('{') ? trimmed : null;
  }

  static ({String content, String? finishReason, StreamEvent? usage})?
      _decodeChunk(String payload) {
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;

      final choices = json['choices'];
      var content = '';
      String? finishReason;
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final delta = first['delta'];
          if (delta is Map && delta['content'] is String) {
            content = delta['content'] as String;
          }
          // Non-streaming servers answer a stream request with a whole
          // message. Reading it means those work too instead of appearing
          // to return nothing.
          final message = first['message'];
          if (content.isEmpty &&
              message is Map &&
              message['content'] is String) {
            content = message['content'] as String;
          }
          final fr = first['finish_reason'];
          if (fr is String) finishReason = fr;
        }
      }

      StreamEvent? usage;
      final u = json['usage'];
      if (u is Map) {
        final input = u['prompt_tokens'];
        final output = u['completion_tokens'];
        if (input is int && output is int) {
          usage = StreamEvent.usage(
            inputTokens: input,
            outputTokens: output,
            totalTokens: (u['total_tokens'] as int?) ?? input + output,
          );
        }
      }

      return (content: content, finishReason: finishReason, usage: usage);
    } catch (_) {
      // One malformed chunk must not end the turn — the rest of the answer is
      // still worth having.
      return null;
    }
  }

  /// Turns an HTTP status into something the user can act on.
  static String _explain(int status, String body, String model) {
    if (status == 404) {
      return 'The local server does not know a model called "$model". Check '
          'the name matches what it is serving.';
    }
    if (status == 400 && body.contains('context')) {
      return 'This conversation is longer than the local model\'s context '
          'window. Start a new chat, or use a model with a larger window.';
    }
    if (status == 503) {
      return 'The local model is still loading. Try again in a moment.';
    }
    final snippet = body.trim();
    return 'The local server refused the request ($status)'
        '${snippet.isEmpty ? '.' : ': ${snippet.substring(0, snippet.length.clamp(0, 200))}'}';
  }
}
