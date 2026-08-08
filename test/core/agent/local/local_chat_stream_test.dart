import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/local/local_chat_stream.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';

/// Serves a canned SSE body so the adapter is tested against a real socket
/// rather than a mock of our own assumptions.
Future<HttpServer> serve(
  String body, {
  int status = 200,
  void Function(Map<String, dynamic> request)? onRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (onRequest != null) {
      final raw = await utf8.decoder.bind(req).join();
      onRequest({
        'path': req.uri.path,
        'body': raw,
        'contentLength': req.contentLength,
        'transferEncoding':
            req.headers.value('transfer-encoding') ?? '',
      });
    }
    req.response.statusCode = status;
    req.response.write(body);
    await req.response.close();
  });
  return server;
}

String get _happyStream => [
      'data: {"choices":[{"delta":{"content":"Hel"}}]}',
      '',
      'data: {"choices":[{"delta":{"content":"lo"}}]}',
      'data: {"choices":[{"delta":{},"finish_reason":"stop"}],'
          '"usage":{"prompt_tokens":11,"completion_tokens":2,"total_tokens":13}}',
      'data: [DONE]',
      '',
    ].join('\n');

void main() {
  late HttpServer server;
  tearDown(() async => server.close(force: true));

  Future<List<StreamEvent>> collect(HttpServer s,
          {String model = 'test-model'}) =>
      LocalChatStream.send(
        baseUrl: 'http://127.0.0.1:${s.port}',
        model: model,
        messages: const [
          {'role': 'user', 'content': 'hi'}
        ],
      ).toList();

  test('an OpenAI stream arrives as the events the app already renders',
      () async {
    server = await serve(_happyStream);
    final events = await collect(server);

    expect(events.first, isA<StreamEventStart>());
    final tokens = [
      for (final e in events)
        if (e is StreamEventToken) e.content,
    ];
    expect(tokens.join(), 'Hello');

    final usage = events.whereType<StreamEventUsage>().single;
    expect(usage.inputTokens, 11);
    expect(usage.totalTokens, 13);

    final done = events.whereType<StreamEventDone>().single;
    expect(done.finishReason, 'stop');
    expect(done.truncated, isFalse);
  });

  test('hitting the context limit sets the flag the Continue pill reads',
      () async {
    server = await serve([
      'data: {"choices":[{"delta":{"content":"cut off"}}]}',
      'data: {"choices":[{"delta":{},"finish_reason":"length"}]}',
      'data: [DONE]',
    ].join('\n'));

    final done = (await collect(server)).whereType<StreamEventDone>().single;
    expect(done.truncated, isTrue);
  });

  test('a runtime that emits bare NDJSON works too', () async {
    // llama-server has shipped both shapes. A parser that only knows SSE
    // produces a silently empty answer against the other.
    server = await serve([
      '{"choices":[{"delta":{"content":"bare"}}]}',
      '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
    ].join('\n'));

    final tokens = [
      for (final e in await collect(server))
        if (e is StreamEventToken) e.content,
    ];
    expect(tokens.join(), 'bare');
  });

  test('a non-streaming reply is still read', () async {
    // Some servers ignore stream:true and answer with a whole message.
    server = await serve(
      'data: {"choices":[{"message":{"content":"whole answer"},'
      '"finish_reason":"stop"}]}',
    );
    final tokens = [
      for (final e in await collect(server))
        if (e is StreamEventToken) e.content,
    ];
    expect(tokens.join(), 'whole answer');
  });

  test('one malformed chunk does not cost the rest of the answer', () async {
    server = await serve([
      'data: {"choices":[{"delta":{"content":"good "}}]}',
      'data: {not json at all',
      'data: {"choices":[{"delta":{"content":"still here"}}]}',
      'data: [DONE]',
    ].join('\n'));

    final tokens = [
      for (final e in await collect(server))
        if (e is StreamEventToken) e.content,
    ];
    expect(tokens.join(), 'good still here');
  });

  test('an unknown model name says which name was wrong', () async {
    // 404 from a local server almost always means the model id does not
    // match what it is serving, and saying so saves the user guessing.
    server = await serve('{"error":"model not found"}', status: 404);
    final err = (await collect(server, model: 'not-pulled'))
        .whereType<StreamEventError>()
        .single;
    expect(err.message, contains('not-pulled'));
    expect(err.code, '404');
  });

  test('a still-loading model is distinguishable from a broken one', () async {
    server = await serve('loading', status: 503);
    final err =
        (await collect(server)).whereType<StreamEventError>().single;
    expect(err.message, contains('still loading'));
  });

  test('an empty stream is an error, not a silent empty answer', () async {
    // Otherwise it looks to the user like the model ignored them.
    server = await serve('data: [DONE]');
    final events = await collect(server);
    expect(events.whereType<StreamEventDone>(), isEmpty);
    expect(
      events.whereType<StreamEventError>().single.message,
      contains('returned nothing'),
    );
  });

  test('the whole conversation is sent, because the server has no memory',
      () async {
    // The one structural difference from our own backend: it is stateless, so
    // sending only the latest message would lose the conversation.
    Map<String, dynamic>? seen;
    server = await serve(_happyStream, onRequest: (r) => seen = r);

    await LocalChatStream.send(
      baseUrl: 'http://127.0.0.1:${server.port}',
      model: 'm',
      systemPrompt: 'be terse',
      messages: const [
        {'role': 'user', 'content': 'first'},
        {'role': 'assistant', 'content': 'reply'},
        {'role': 'user', 'content': 'second'},
      ],
    ).toList();

    expect(seen?['path'], '/v1/chat/completions');
    final body = seen?['body'] as String? ?? '';
    expect(body, contains('be terse'));
    expect(body, contains('first'));
    expect(body, contains('reply'));
    expect(body, contains('second'));
    expect(body, contains('"stream":true'));
  });

  test('the body is sent with a length, not chunked', () async {
    // Dart chunks a request body by default when the length is unset, and the
    // small C++ servers this talks to parse that poorly. Measured against a
    // stub that read a chunked body as empty: the model answered as though the
    // conversation had no messages in it.
    Map<String, dynamic>? seen;
    server = await serve(_happyStream, onRequest: (r) => seen = r);

    await collect(server);

    expect(seen?['contentLength'], isNotNull);
    expect(seen?['contentLength'], greaterThan(0));
    expect(seen?['transferEncoding'], isNot(contains('chunked')));
  });
}
