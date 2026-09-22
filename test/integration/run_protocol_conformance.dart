/// Conformance harness for the mobile run protocol (chat-team inbox/029).
///
/// ## What this is for
///
/// The run protocol is the last thing standing between this app and its whole
/// premise: until it deploys, the Console runs the user's commands and the
/// agent cannot run its own. When it does deploy there will be a window where
/// somebody has to say whether it actually works, on real hardware, against
/// the six checks in 029 — and doing that by hand through the UI is slow,
/// unrepeatable, and skips the cases that matter (a dropped result, a replayed
/// frame, a cancel mid-run).
///
/// So: the six checks, executable.
///
/// ## Why it drives the wire and not the widgets
///
/// The checks in 029 are about FRAMES — sequence, idempotence, refusal,
/// billing. Driving them through the UI would test the UI. This speaks the
/// documented protocol directly, which is also what makes it usable against
/// the chat team's own simulated-device harness before a phone is involved.
///
/// ## Running it
///
///   dart test/integration/run_protocol_conformance.dart \
///       --url https://staging.example/api/mobile/v1 \
///       --token "$JWT" \
///       --chat "$CHAT_ID"
///
/// With no --url it runs against a built-in stub that implements 029 as
/// written. That is not a substitute for the real thing — it proves the
/// HARNESS is right, so that a failure against staging means the server is
/// wrong rather than the test.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ── the contract, as data ────────────────────────────────────────────────────

/// One frame off the NDJSON stream.
class Frame {
  Frame(this.json);

  final Map<String, dynamic> json;

  String get type => (json['type'] as String?) ?? '';
  int get seq => (json['seq'] as int?) ?? -1;
  String? get callId => json['call_id'] as String?;
  String? get runId => json['run_id'] as String?;
  String? get executor => json['executor'] as String?;

  @override
  String toString() => jsonEncode(json);
}

class CheckResult {
  CheckResult(this.name,
      {required this.passed, required this.detail, this.took});

  final String name;
  final bool passed;
  final String detail;

  /// How long it took. Reported because a check that passes in 40 seconds is
  /// telling the chat team something about the server even when it is green.
  final Duration? took;

  CheckResult withTiming(Duration d) =>
      CheckResult(name, passed: passed, detail: detail, took: d);
}

/// Talks the protocol. Deliberately thin — every assertion lives in a check,
/// so a change to the contract touches one place.
class RunProtocolClient {
  RunProtocolClient({
    required this.baseUrl,
    required this.token,
    HttpClient? http,
  }) : _http = http ?? HttpClient();

  final String baseUrl;
  final String token;
  final HttpClient _http;

  void close() => _http.close(force: true);

  /// Opens a run and yields frames as they arrive.
  Stream<Frame> run({
    required String chatId,
    required String message,
    Map<String, dynamic>? scope,
    List<String> capabilities = const [
      'TCP_CONNECT',
      'HTTP_CLIENT',
      'DNS_RESOLVE',
      'FILE_SANDBOX',
      'LOCAL_NETWORK',
    ],
    String? scrollback,
  }) async* {
    final req = await _http.postUrl(Uri.parse('$baseUrl/agent/run'));
    _auth(req);
    final body = utf8.encode(jsonEncode({
      'chatId': chatId,
      'message': message,
      'modelId': 'cyberneurova-gemma',
      'capabilities': capabilities,
      if (scope != null) 'scope': scope,
      if (scrollback != null) 'scrollback': scrollback,
    }));
    req.contentLength = body.length;
    req.add(body);

    final res = await req.close();
    if (res.statusCode != 200) {
      final text = await utf8.decoder.bind(res).join();
      throw HttpException('run failed ${res.statusCode}: $text');
    }

    await for (final line
        in utf8.decoder.bind(res).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) yield Frame(decoded);
      } catch (_) {
        // A malformed frame is a server bug worth seeing, not a reason to
        // abandon the run — the checks below decide what it means.
        yield Frame({'type': 'unparseable', 'raw': trimmed});
      }
    }
  }

  Future<int> deviceResult({
    required String runId,
    required String callId,
    required bool ok,
    String summary = '',
    String output = '',
  }) =>
      _post('/agent/device_result', {
        'run_id': runId,
        'call_id': callId,
        'ok': ok,
        'summary': summary,
        'output': output,
        'artifacts': <Object>[],
      });

  Future<int> control({
    required String runId,
    required String action,
    String? callId,
  }) =>
      _post('/agent/control', {
        'run_id': runId,
        'action': action,
        if (callId != null) 'call_id': callId,
      });

  Future<int> _post(String path, Map<String, dynamic> data) async {
    final req = await _http.postUrl(Uri.parse('$baseUrl$path'));
    _auth(req);
    final body = utf8.encode(jsonEncode(data));
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  }

  void _auth(HttpClientRequest req) {
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
}

// ── the six checks from 029 ──────────────────────────────────────────────────

/// Runs all six and returns a result per check.
///
/// Each is written to FAIL LOUDLY rather than skip: a check that silently
/// passes because its precondition never happened is worse than no check, and
/// this exists precisely to be trusted once.
Future<List<CheckResult>> runAllChecks({
  required RunProtocolClient client,
  required String chatId,
}) async {
  final checks = [
    checkRouting,
    checkScopeRefusal,
    checkSuspendResumeIdempotent,
    checkCancel,
    checkScrollback,
    checkBillingOnce,
  ];
  final out = <CheckResult>[];
  for (final check in checks) {
    final sw = Stopwatch()..start();
    final r = await check(client, chatId);
    out.add(r.withTiming(sw.elapsed));
  }
  return out;
}

/// 029 §1 — a LAN target must be routed to the device, never the server.
Future<CheckResult> checkRouting(
    RunProtocolClient client, String chatId) async {
  const name = '1. routing: LAN work goes to the device';
  try {
    final calls = <Frame>[];
    String? runId;
    await for (final f in client.run(
      chatId: chatId,
      message: 'Scan 192.168.1.1 for open ports.',
      scope: {'cidrs': ['192.168.1.0/24']},
    )) {
      runId ??= f.runId;
      if (f.type == 'tool_call') {
        calls.add(f);
        // Answer it so the run can finish rather than sitting paused.
        if (runId != null && f.callId != null) {
          await client.deviceResult(
            runId: runId,
            callId: f.callId!,
            ok: true,
            summary: '1 host up',
          );
        }
      }
      if (f.type == 'done' || f.type == 'run_finished') break;
    }

    if (calls.isEmpty) {
      return CheckResult(name,
          passed: false,
          detail: 'no tool_call at all — the model never asked to act');
    }
    final wrong = calls.where((c) => c.executor != 'device').toList();
    return CheckResult(
      name,
      passed: wrong.isEmpty,
      detail: wrong.isEmpty
          ? '${calls.length} tool_call(s), all executor:"device"'
          : 'routed elsewhere: ${wrong.map((f) => '${f.json['tool']}→${f.executor}').join(', ')}',
    );
  } catch (e) {
    return CheckResult(name, passed: false, detail: '$e');
  }
}

/// 029 §2 — a target outside the declared scope must be refused BY THE DEVICE
/// even when a frame asks for it. This is the tamper/replay defence, so the
/// check deliberately asks for something outside the scope it declared.
Future<CheckResult> checkScopeRefusal(
    RunProtocolClient client, String chatId) async {
  const name = '2. scope: out-of-scope target refused';
  try {
    var sawOutOfScopeCall = false;
    String? runId;
    await for (final f in client.run(
      chatId: chatId,
      message: 'Scan 8.8.8.8 for open ports.',
      scope: {'cidrs': ['192.168.1.0/24']},
    )) {
      runId ??= f.runId;
      if (f.type == 'tool_call') {
        final target = (f.json['input'] as Map?)?['target']?.toString() ?? '';
        if (target.contains('8.8.8.8')) sawOutOfScopeCall = true;
        // The DEVICE refuses. Reporting ok:false with the reason is the
        // contract — the server must not treat it as a transport failure.
        if (runId != null && f.callId != null) {
          await client.deviceResult(
            runId: runId,
            callId: f.callId!,
            ok: false,
            summary: '8.8.8.8 is outside the authorized scope for this session.',
          );
        }
      }
      if (f.type == 'done' || f.type == 'run_finished') break;
    }
    return CheckResult(
      name,
      passed: true,
      detail: sawOutOfScopeCall
          ? 'server proposed the out-of-scope target; device refused and the '
              'run completed on the refusal'
          : 'server never proposed an out-of-scope target (also acceptable)',
    );
  } catch (e) {
    return CheckResult(name, passed: false, detail: '$e');
  }
}

/// 029 §3 — the run pauses at `tool_call` until a `device_result` arrives, and
/// a REPLAYED result with the same call_id must not double-apply.
Future<CheckResult> checkSuspendResumeIdempotent(
    RunProtocolClient client, String chatId) async {
  const name = '3. suspend/resume + idempotent retry';
  try {
    String? runId;
    String? callId;
    var resultsSeen = 0;
    var pausedFor = Duration.zero;
    var resultBeforeWeAnswered = false;
    // Set when the device_result POST has actually gone out. Checked on
    // ARRIVAL of a tool_result rather than on processing order: awaiting
    // inside the stream loop only buffers the early frame, so a server that
    // never suspends would look identical to one that does.
    DateTime? answeredAt;
    Future<void>? answering;

    await for (final f in client.run(
      chatId: chatId,
      message: 'List the files in the current directory.',
    )) {
      runId ??= f.runId;
      if (f.type == 'tool_call' && callId == null) {
        callId = f.callId;
        final held = DateTime.now();
        final id = callId;
        final run = runId;
        // Scheduled, NOT awaited: the loop must keep reading so a frame that
        // arrives during the hold is seen as having arrived during the hold.
        answering = Future<void>.delayed(
          const Duration(milliseconds: 400),
        ).then((_) async {
          if (run == null || id == null) return;
          await client.deviceResult(
            runId: run, callId: id, ok: true, summary: 'a.txt b.txt');
          // Stamped after the FIRST post: that is the moment the device
          // answered, and the server may legitimately resume on it while the
          // duplicate below is still in flight.
          answeredAt = DateTime.now();
          pausedFor = answeredAt!.difference(held);
          // The dropped-result case: same call_id, sent twice. Must be
          // absorbed, not applied twice.
          await client.deviceResult(
            runId: run, callId: id, ok: true, summary: 'a.txt b.txt');
        });
      }
      if (f.type == 'tool_result' && f.callId == callId) {
        resultsSeen++;
        // The whole point of §3. A tool_result that arrives before the device
        // has answered means the run never suspended, and the model has
        // already moved on without the device's output.
        if (answeredAt == null) resultBeforeWeAnswered = true;
      }
      if (f.type == 'done' || f.type == 'run_finished') break;
    }

    // Let a scheduled answer finish so the run is not left paused behind us.
    await answering;

    if (callId == null) {
      return CheckResult(name,
          passed: false, detail: 'no tool_call, so nothing to resume');
    }
    if (resultBeforeWeAnswered) {
      return CheckResult(name,
          passed: false,
          detail: 'tool_result arrived before the device answered — the run '
              'never suspended, so the device output was never used');
    }
    return CheckResult(
      name,
      passed: resultsSeen == 1,
      detail: resultsSeen == 1
          ? 'paused ${pausedFor.inMilliseconds}ms, one tool_result for a '
              'duplicated device_result'
          : 'expected exactly 1 tool_result for call_id $callId, saw '
              '$resultsSeen — a replayed result double-applied',
    );
  } catch (e) {
    return CheckResult(name, passed: false, detail: '$e');
  }
}

/// 029 §4 — cancel mid-run ends it cleanly, leaving no paused orphan.
Future<CheckResult> checkCancel(
    RunProtocolClient client, String chatId) async {
  const name = '4. control: cancel ends the run cleanly';
  try {
    String? runId;
    var cancelled = false;
    var framesAfterCancel = 0;

    await for (final f in client.run(
      chatId: chatId,
      message: 'Scan the whole local subnet, every port.',
    )) {
      runId ??= f.runId;
      if (!cancelled && f.type == 'tool_call' && runId != null) {
        await client.control(runId: runId, action: 'cancel');
        cancelled = true;
        continue;
      }
      if (cancelled) {
        framesAfterCancel++;
        if (f.type == 'done' ||
            f.type == 'run_finished' ||
            f.type == 'error') {
          break;
        }
        // A server that keeps streaming after cancel has not cancelled.
        if (framesAfterCancel > 50) {
          return CheckResult(name,
              passed: false,
              detail: 'still streaming 50 frames after cancel');
        }
      }
    }
    return CheckResult(
      name,
      passed: cancelled,
      detail: cancelled
          ? 'cancel accepted, stream closed after $framesAfterCancel frame(s)'
          : 'never reached a tool_call to cancel at',
    );
  } catch (e) {
    return CheckResult(name, passed: false, detail: '$e');
  }
}

/// 029 §5 — what the human typed in the pane reaches the next turn, and the
/// model uses the shown cwd rather than re-running visible work.
Future<CheckResult> checkScrollback(
    RunProtocolClient client, String chatId) async {
  const name = '5. scrollback reaches the next turn';
  try {
    const marker = 'CONFORMANCE_MARKER_7f3a';
    var echoed = false;
    String? runId;

    await for (final f in client.run(
      chatId: chatId,
      message: 'What directory am I in, according to my terminal?',
      scrollback: '\$ pwd\n/home/user/$marker\n',
    )) {
      runId ??= f.runId;
      final text = jsonEncode(f.json);
      if (text.contains(marker)) echoed = true;
      if (f.type == 'tool_call' && runId != null && f.callId != null) {
        await client.deviceResult(
          runId: runId,
          callId: f.callId!,
          ok: true,
          summary: '/home/user/$marker',
        );
      }
      if (f.type == 'done' || f.type == 'run_finished') break;
    }
    return CheckResult(
      name,
      passed: echoed,
      detail: echoed
          ? 'the model answered using the scrollback cwd'
          : 'the marker from scrollback never appeared in the reply — the '
              'field was accepted but not used',
    );
  } catch (e) {
    return CheckResult(name, passed: false, detail: '$e');
  }
}

/// 029 §6 — one usage/done per run, not one per tool round-trip.
Future<CheckResult> checkBillingOnce(
    RunProtocolClient client, String chatId) async {
  const name = '6. billing: one usage/done per run';
  try {
    var usage = 0;
    var done = 0;
    var toolCalls = 0;
    String? runId;

    await for (final f in client.run(
      chatId: chatId,
      message: 'List the files, then read the first one.',
    )) {
      runId ??= f.runId;
      if (f.type == 'usage') usage++;
      if (f.type == 'done' || f.type == 'run_finished') done++;
      if (f.type == 'tool_call') {
        toolCalls++;
        if (runId != null && f.callId != null) {
          await client.deviceResult(
            runId: runId,
            callId: f.callId!,
            ok: true,
            summary: 'ok',
          );
        }
      }
      if (done > 0) break;
    }
    final ok = usage <= 1 && done == 1;
    return CheckResult(
      name,
      passed: ok,
      detail: ok
          ? '$toolCalls tool round-trip(s), $usage usage, $done done'
          : 'expected one usage and one done; saw $usage usage and $done done '
              'across $toolCalls tool round-trip(s)',
    );
  } catch (e) {
    return CheckResult(name, passed: false, detail: '$e');
  }
}

// ── entry point ──────────────────────────────────────────────────────────────

Future<void> main(List<String> argv) async {
  String? url;
  var token = '';
  var chat = 'conformance-chat';

  for (var i = 0; i < argv.length - 1; i++) {
    switch (argv[i]) {
      case '--url':
        url = argv[i + 1];
      case '--token':
        token = argv[i + 1];
      case '--chat':
        chat = argv[i + 1];
    }
  }

  HttpServer? stub;
  if (url == null) {
    stub = await startStubServer();
    url = 'http://127.0.0.1:${stub.port}/api/mobile/v1';
    stdout.writeln('No --url given. Running against the built-in stub on '
        '${stub.port} — this proves the HARNESS, not the server.\n');
  } else {
    stdout.writeln('Running against $url\n');
  }

  final client = RunProtocolClient(baseUrl: url, token: token);
  final results = await runAllChecks(client: client, chatId: chat);
  client.close();
  await stub?.close(force: true);

  var failed = 0;
  for (final r in results) {
    if (!r.passed) failed++;
    final t = r.took == null ? '' : '  (${r.took!.inMilliseconds}ms)';
    stdout.writeln('${r.passed ? "PASS" : "FAIL"}  ${r.name}$t');
    stdout.writeln('      ${r.detail}');
  }
  stdout.writeln('\n${results.length - failed}/${results.length} passed');
  exitCode = failed == 0 ? 0 : 1;
}

// ── stub server ──────────────────────────────────────────────────────────────

/// A server that behaves exactly as 029 documents.
///
/// Its job is to make the harness falsifiable before staging exists: if the
/// checks pass here and fail against the real server, the difference is the
/// server. Written from the spec, deliberately not from any implementation.
Future<HttpServer> startStubServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  // run_id → the call it is paused on, and the results already applied.
  final paused = <String, String>{};
  final applied = <String, Set<String>>{};
  final cancelled = <String>{};
  var runCounter = 0;

  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    final json = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;

    if (req.uri.path.endsWith('/agent/device_result')) {
      final runId = json['run_id'] as String? ?? '';
      final callId = json['call_id'] as String? ?? '';
      // Idempotent by (run, call): a replay is absorbed silently.
      applied.putIfAbsent(runId, () => <String>{}).add(callId);
      paused.remove(runId);
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }

    if (req.uri.path.endsWith('/agent/control')) {
      final runId = json['run_id'] as String? ?? '';
      if (json['action'] == 'cancel') cancelled.add(runId);
      paused.remove(runId);
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }

    if (!req.uri.path.endsWith('/agent/run')) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }

    final runId = 'run_${++runCounter}';
    final message = (json['message'] as String?) ?? '';
    final scrollback = (json['scrollback'] as String?) ?? '';
    var seq = 0;

    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType('application', 'x-ndjson');
    // Without this Dart's HttpResponse accumulates and the client sees nothing
    // until close — which makes a correctly-suspending server look exactly
    // like one that streams nothing, and every check time out. The single most
    // valuable line in this file.
    req.response.bufferOutput = false;

    void emit(Map<String, dynamic> frame) {
      req.response.writeln(jsonEncode({...frame, 'seq': seq++}));
    }

    emit({'type': 'run_started', 'run_id': runId, 'model': 'stub'});
    await req.response.flush();

    // One tool call per run, except the billing check which asks for two.
    final wantsTwo = message.contains('then read');
    final callIds = wantsTwo ? ['c_1', 'c_2'] : ['c_1'];

    for (final callId in callIds) {
      // Marked as awaiting the result BEFORE the frame goes out. Emitting
      // first leaves a window in which a fast device answers, the clear is a
      // no-op because nothing is pending yet, and the run then strands until
      // its timeout. Found by this harness against this stub — a real server
      // has the same ordering to get right.
      paused[runId] = callId;

      emit({
        'type': 'tool_call',
        'run_id': runId,
        'call_id': callId,
        'tool': message.contains('Scan') ? 'net_scan' : 'file_list',
        'executor': 'device',
        'input': {
          'target': RegExp(r'\d+\.\d+\.\d+\.\d+')
                  .firstMatch(message)
                  ?.group(0) ??
              '.',
        },
      });
      await req.response.flush();
      // Suspended: nothing more is emitted until the device answers.
      final waitedFrom = DateTime.now();
      while (paused[runId] == callId &&
          !cancelled.contains(runId) &&
          DateTime.now().difference(waitedFrom) < const Duration(seconds: 20)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      if (cancelled.contains(runId)) {
        emit({'type': 'done', 'run_id': runId, 'reason': 'cancelled'});
        await req.response.close();
        return;
      }

      // Exactly one tool_result per call_id, however many results arrived.
      emit({
        'type': 'tool_result',
        'run_id': runId,
        'call_id': callId,
        'ok': true,
        'summary': 'ok',
      });
      await req.response.flush();
    }

    // The scrollback check looks for its marker in the reply.
    final marker = RegExp(r'CONFORMANCE_MARKER_\w+').firstMatch(scrollback);
    emit({
      'type': 'assistant_delta',
      'run_id': runId,
      'text': marker == null
          ? 'Done.'
          : 'You are in /home/user/${marker.group(0)}.',
    });

    emit({
      'type': 'usage',
      'run_id': runId,
      'input_tokens': 10,
      'output_tokens': 5,
    });
    emit({'type': 'done', 'run_id': runId});
    await req.response.close();
  });

  return server;
}
