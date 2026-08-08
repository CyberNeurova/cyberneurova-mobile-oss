import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'run_protocol_conformance.dart';

/// Does the harness actually CATCH anything?
///
/// A conformance suite that only ever passes is decoration. These point it at
/// servers that break each rule on purpose, and assert the matching check goes
/// red — so that when it is finally aimed at staging, a green result means
/// something and a red one is believable.
void main() {
  late HttpServer server;
  tearDown(() async => server.close(force: true));

  /// Runs ONE check against [s]. Running all six per test made each case wait
  /// on five irrelevant runs and blew the timeout.
  Future<CheckResult> one(
    HttpServer s,
    Future<CheckResult> Function(RunProtocolClient, String) check,
  ) async {
    final client = RunProtocolClient(
      baseUrl: 'http://127.0.0.1:${s.port}/api/mobile/v1',
      token: 'test',
    );
    final r = await check(client, 'c');
    client.close();
    return r;
  }

  test('the honest stub passes all six', () async {
    server = await startStubServer();
    final client = RunProtocolClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/mobile/v1',
      token: 'test',
    );
    final results = await runAllChecks(client: client, chatId: 'c');
    client.close();
    for (final r in results) {
      expect(r.passed, isTrue, reason: '${r.name}: ${r.detail}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('catches work routed to the server instead of the device', () async {
    // The failure that would quietly send someone's LAN scan through our
    // datacentre — which cannot even reach their network.
    server = await _misbehaving(executor: 'server');
    expect((await one(server, checkRouting)).passed, isFalse);
  });

  test('catches a replayed device_result being applied twice', () async {
    // A dropped result is retried with the same call_id. If the server applies
    // both, the model sees the tool run twice and acts on a doubled world.
    server = await _misbehaving(duplicateToolResult: true);
    final r = await one(server, checkSuspendResumeIdempotent);
    expect(r.passed, isFalse);
    expect(r.detail, contains('double-applied'));
  });

  test('catches a run that never suspends at tool_call', () async {
    // If it does not pause, the device's answer arrives too late to matter and
    // the model has already carried on without it.
    server = await _misbehaving(neverSuspend: true);
    final r = await one(server, checkSuspendResumeIdempotent);
    expect(r.passed, isFalse);
    expect(r.detail, contains('never suspended'));
  });

  test('catches billing once per tool round-trip instead of per run',
      () async {
    // The one that costs the user money rather than correctness.
    server = await _misbehaving(usagePerToolCall: true);
    final r = await one(server, checkBillingOnce);
    expect(r.passed, isFalse);
    expect(r.detail, contains('usage'));
  });

  test('catches scrollback being accepted and ignored', () async {
    // Accepting the field and dropping it is worse than rejecting it: the
    // client looks correct and the model re-runs work already on screen.
    server = await _misbehaving(ignoreScrollback: true);
    expect((await one(server, checkScrollback)).passed, isFalse);
  });
}

/// A server that breaks exactly one rule.
Future<HttpServer> _misbehaving({
  String executor = 'device',
  bool duplicateToolResult = false,
  bool neverSuspend = false,
  bool usagePerToolCall = false,
  bool ignoreScrollback = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final paused = <String, String>{};
  final cancelled = <String>{};
  var runCounter = 0;

  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    final json = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;

    if (req.uri.path.endsWith('/agent/device_result')) {
      paused.remove(json['run_id']);
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }
    if (req.uri.path.endsWith('/agent/control')) {
      if (json['action'] == 'cancel') cancelled.add(json['run_id'] as String);
      paused.remove(json['run_id']);
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }

    final runId = 'run_${++runCounter}';
    final message = (json['message'] as String?) ?? '';
    final scrollback = (json['scrollback'] as String?) ?? '';
    var seq = 0;
    void emit(Map<String, dynamic> f) =>
        req.response.writeln(jsonEncode({...f, 'seq': seq++}));

    req.response.statusCode = 200;
    // Same trap as the honest stub: without this the client sees nothing until
    // close, and every check times out for a reason that has nothing to do
    // with the rule under test.
    req.response.bufferOutput = false;
    emit({'type': 'run_started', 'run_id': runId});
    await req.response.flush();

    final calls = message.contains('then read') ? ['c_1', 'c_2'] : ['c_1'];
    for (final callId in calls) {
      emit({
        'type': 'tool_call',
        'run_id': runId,
        'call_id': callId,
        'tool': 'net_scan',
        'executor': executor,
        'input': {'target': '192.168.1.1'},
      });
      await req.response.flush();

      if (!neverSuspend) {
        paused[runId] = callId;
        final from = DateTime.now();
        while (paused[runId] == callId &&
            !cancelled.contains(runId) &&
            DateTime.now().difference(from) < const Duration(seconds: 10)) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      if (cancelled.contains(runId)) {
        emit({'type': 'done', 'run_id': runId});
        await req.response.close();
        return;
      }

      emit({
        'type': 'tool_result',
        'run_id': runId,
        'call_id': callId,
        'ok': true,
      });
      if (duplicateToolResult) {
        emit({
          'type': 'tool_result',
          'run_id': runId,
          'call_id': callId,
          'ok': true,
        });
      }
      if (usagePerToolCall) {
        emit({'type': 'usage', 'run_id': runId, 'output_tokens': 1});
      }
      await req.response.flush();
    }

    final marker = RegExp(r'CONFORMANCE_MARKER_\w+').firstMatch(scrollback);
    emit({
      'type': 'assistant_delta',
      'run_id': runId,
      'text': (marker == null || ignoreScrollback)
          ? 'Done.'
          : 'You are in /home/user/${marker.group(0)}.',
    });
    if (!usagePerToolCall) {
      emit({'type': 'usage', 'run_id': runId, 'output_tokens': 5});
    }
    emit({'type': 'done', 'run_id': runId});
    await req.response.close();
  });

  return server;
}
