import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';

/// HTTP request with full control of method, headers, body and TLS.
///
/// Pure Dart via `HttpClient`, so it runs on both platforms with no platform
/// channel. Like the scan tools, the value is *where* it runs: probing
/// `http://192.168.1.1` only works from the phone — a server-side container
/// has no route to the user's LAN.
///
/// `insecure_tls` exists because the interesting targets on a LAN (routers,
/// NAS boxes, printers, IP cameras) almost all serve self-signed certs. A
/// probe that refuses them is useless for the job this tool is for. It is
/// opt-in per call and reported in the output so it never happens silently.
class HttpProbeTool implements DeviceTool {
  @override
  String get name => 'http_probe';

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.httpClient};

  /// Uniform `target` per `docs/shell/06-AGENT-INTEGRATION.md` §2 — the scope
  /// checker parses one field name across every network tool.
  @override
  String? get targetArgKey => 'target';

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  /// Bodies are truncated before they reach the model. A 4 MB page would blow
  /// the context window and tell the agent nothing the first few KB didn't.
  static const int _maxBodyChars = 8000;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final rawTarget = (args['target'] as String?)?.trim() ?? '';
    if (rawTarget.isEmpty) {
      return const DeviceToolResult.failure('target is required');
    }

    // Bare host/IP is the common case from a scan result ("port 80 open on
    // 192.168.1.1"), so default the scheme rather than making the model
    // remember to add it.
    final uri = Uri.tryParse(
      rawTarget.contains('://') ? rawTarget : 'http://$rawTarget',
    );
    if (uri == null || uri.host.isEmpty) {
      return DeviceToolResult.failure('Not a usable URL: $rawTarget');
    }

    final method = ((args['method'] as String?) ?? 'GET').toUpperCase();
    final headers = (args['headers'] as Map?)?.cast<String, dynamic>() ?? {};
    final body = args['body'] as String?;
    final followRedirects = args['follow_redirects'] as bool? ?? true;
    final insecureTls = args['insecure_tls'] as bool? ?? false;
    final timeout = Duration(
      seconds: (args['timeout_s'] as num?)?.toInt().clamp(1, 300) ?? 30,
    );

    final client = HttpClient()..connectionTimeout = timeout;
    if (insecureTls) {
      client.badCertificateCallback = (_, __, ___) => true;
    }

    final started = DateTime.now();
    try {
      context.onProgress('$method ${uri.toString()}');

      final request = await client
          .openUrl(method, uri)
          .timeout(timeout, onTimeout: () => throw TimeoutException('connect'));
      request.followRedirects = followRedirects;
      headers.forEach((k, v) => request.headers.set(k, '$v'));
      if (body != null && body.isNotEmpty) {
        request.add(utf8.encode(body));
      }

      if (context.isCancelled()) {
        request.abort();
        return const DeviceToolResult.failure('Cancelled');
      }

      final response = await request.close().timeout(timeout);
      final elapsed = DateTime.now().difference(started);

      // Decode leniently: a device on the LAN may serve any charset, or
      // binary. Never let a decode error lose an otherwise-good result.
      final bytes = await response
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
          .timeout(timeout);
      final text = _decodeLenient(bytes);

      final headerLines = <String>[];
      response.headers.forEach((k, v) => headerLines.add('  $k: ${v.join(', ')}'));

      final server = response.headers.value('server');
      final location = response.headers.value('location');
      final title = _titleOf(text);

      // The summary is what the collapsed card shows, so pack it with the
      // things that identify a host: status, server banner, page title.
      final summary = StringBuffer('${response.statusCode} ${_reason(response)}')
        ..write(' · ${_humanBytes(bytes.length)}')
        ..write(' · ${elapsed.inMilliseconds}ms');
      if (server != null) summary.write(' · $server');
      if (title != null) summary.write(' · "$title"');
      if (location != null) summary.write(' → $location');

      final truncated = text.length > _maxBodyChars;
      final shownBody =
          truncated ? '${text.substring(0, _maxBodyChars)}\n… truncated' : text;

      final output = StringBuffer()
        ..writeln('$method ${uri.toString()}')
        ..writeln('${response.statusCode} ${_reason(response)}')
        ..writeln(headerLines.join('\n'))
        ..writeln()
        ..write(shownBody);
      if (insecureTls) {
        output.writeln();
        output.writeln('[TLS verification was disabled for this request]');
      }

      return DeviceToolResult(
        ok: true,
        summary: summary.toString(),
        output: output.toString(),
      );
    } on TimeoutException {
      return DeviceToolResult.failure(
          'Timed out after ${timeout.inSeconds}s: ${uri.host}');
    } on HandshakeException catch (e) {
      // Worth its own message: on a LAN this nearly always means a
      // self-signed cert, and the fix (insecure_tls) is one argument away.
      return DeviceToolResult.failure(
          'TLS handshake failed for ${uri.host} (${e.message}). '
          'Retry with insecure_tls: true if this host uses a self-signed certificate.');
    } on SocketException catch (e) {
      return DeviceToolResult.failure(
          "Couldn't reach ${uri.host}:${uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80)} — ${e.message}");
    } catch (e) {
      return DeviceToolResult.failure('Request failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  String _reason(HttpClientResponse r) =>
      r.reasonPhrase.isNotEmpty ? r.reasonPhrase : '';

  static String _decodeLenient(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  static String? _titleOf(String html) {
    final m = RegExp(r'<title[^>]*>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    final t = m?.group(1)?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t == null || t.isEmpty) return null;
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }

  static String _humanBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
