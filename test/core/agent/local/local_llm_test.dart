import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/local/local_llm.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('accepts what people actually type on a phone', () {
      // Refusing these is a good way to make the feature unusable: nobody
      // types a scheme on a phone keyboard if they can avoid it.
      expect(LocalLlm.normalizeBaseUrl('localhost:11434'),
          'http://localhost:11434');
      expect(LocalLlm.normalizeBaseUrl('192.168.1.5:8080'),
          'http://192.168.1.5:8080');
      expect(LocalLlm.normalizeBaseUrl('  http://127.0.0.1:8080  '),
          'http://127.0.0.1:8080');
    });

    test('strips the /v1 people paste from a quick-start', () {
      // Every project's README shows the full OpenAI base URL, so this is the
      // most likely thing to end up in the box.
      expect(LocalLlm.normalizeBaseUrl('http://127.0.0.1:8080/v1'),
          'http://127.0.0.1:8080');
      expect(LocalLlm.normalizeBaseUrl('http://127.0.0.1:8080/v1/'),
          'http://127.0.0.1:8080');
      expect(LocalLlm.normalizeBaseUrl('http://box.local/openai/v1'),
          'http://box.local/openai');
    });

    test('rejects what cannot be a URL', () {
      expect(LocalLlm.normalizeBaseUrl(''), isNull);
      expect(LocalLlm.normalizeBaseUrl('   '), isNull);
      expect(LocalLlm.normalizeBaseUrl('http://'), isNull);
    });
  });

  group('parseModels', () {
    test('reads the envelope every local runtime returns', () {
      const body = '{"object":"list","data":['
          '{"id":"qwen2.5-coder-3b","object":"model"},'
          '{"id":"llama3.2:1b","size":1321098329}]}';
      final models = LocalLlm.parseModels(body);
      expect(models.length, 2);
      expect(models.first.id, 'qwen2.5-coder-3b');
      expect(models.first.sizeBytes, isNull);
      expect(models[1].sizeBytes, 1321098329);
    });

    test('drops junk entries instead of failing the whole list', () {
      // One drifted entry must not cost the user every other model — the same
      // rule ModelsResponse already follows for the server's /models.
      const body = '{"data":[{"id":""},{"nope":1},"string",'
          '{"id":"good-one"}]}';
      final models = LocalLlm.parseModels(body);
      expect([for (final m in models) m.id], ['good-one']);
    });

    test('a non-OpenAI body is empty, not an exception', () {
      expect(LocalLlm.parseModels('<html>404</html>'), isEmpty);
      expect(LocalLlm.parseModels('{"error":"nope"}'), isEmpty);
      expect(LocalLlm.parseModels(''), isEmpty);
    });
  });

  group('probe', () {
    late HttpServer server;

    tearDown(() async => server.close(force: true));

    test('finds a server that speaks the OpenAI API', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        expect(req.uri.path, '/v1/models');
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'data': [
              {'id': 'local-test-model'}
            ]
          }));
        req.response.close();
      });

      final found =
          await LocalLlm.probe('http://127.0.0.1:${server.port}');
      expect(found.isUsable, isTrue);
      expect(found.models.single.id, 'local-test-model');
    });

    test('something listening that is NOT a model server is not reachable',
        () async {
      // A port being open proves nothing. Without this check the picker would
      // offer an endpoint that 404s on every message.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.statusCode = 404;
        req.response.close();
      });

      final found = await LocalLlm.probe('http://127.0.0.1:${server.port}');
      expect(found.isUsable, isFalse);
      expect(found.answered, isFalse);
    });

    test('a server with no models is up, not unreachable', () async {
      // Found by accident against a real Ollama with nothing pulled: it
      // answers /v1/models with a null data field. Folding that into "not
      // answering" told the user to check their network when the actual fix
      // is `ollama pull`.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..headers.contentType = ContentType.json
          ..write('{"object":"list","data":null}');
        req.response.close();
      });

      final found = await LocalLlm.probe('http://127.0.0.1:${server.port}');
      expect(found.answered, isTrue, reason: 'something IS listening');
      expect(found.isEmpty, isTrue);
      expect(found.isUsable, isFalse, reason: 'nothing to run yet');
    });

    test('nothing listening is an answer, not a crash', () async {
      // Reserve a port then release it, so we know nothing is on it.
      final tmp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = tmp.port;
      await tmp.close();

      final found = await LocalLlm.probe(
        'http://127.0.0.1:$port',
        timeout: const Duration(milliseconds: 800),
      );
      expect(found.isUsable, isFalse);
      expect(found.answered, isFalse);
      expect(found.baseUrl, 'http://127.0.0.1:$port');

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
  });

  test('known ports name the server people are running', () {
    expect(LocalLlm.flavourForPort(11434), 'Ollama');
    expect(LocalLlm.flavourForPort(8080), 'llama.cpp');
    expect(LocalLlm.flavourForPort(65000), isNull);
  });
}
