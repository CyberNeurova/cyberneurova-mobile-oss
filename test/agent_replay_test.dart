import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';

/// Accepts everything and records what was sent.
class _Channel implements AgentControlChannel {
  final List<AgentControlMessage> sent = [];

  @override
  bool get isConnected => true;

  @override
  Future<void> send(AgentControlMessage message) async => sent.add(message);
}

/// A tool that counts how many times it actually ran — the whole point of
/// these tests is the difference between "we sent one result" and "we did the
/// thing once".
class _CountingTool implements DeviceTool {
  int runs = 0;
  final List<String> order = [];

  @override
  String get name => 'count';

  @override
  Set<DeviceCapability> get requires => const {};

  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    runs++;
    order.add('run$runs');
    // Yields, so a replay arriving while this is in flight is a real race and
    // not something the event loop hides.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return DeviceToolResult(ok: true, summary: 'ran $runs');
  }
}

AgentToolCall _call(String id) => AgentToolCall(
      callId: id,
      tool: 'count',
      input: const {},
      executor: 'device',
    );

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  // DeviceExecutor ends every call through BackgroundRuns, which talks to a
  // platform channel — without the binding that throws from a timer after the
  // test body has already passed, which reads as a random failure in whichever
  // test happens to be running.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Channel channel;
  late _CountingTool tool;
  late AgentSession session;

  setUp(() {
    channel = _Channel();
    tool = _CountingTool();
    session = AgentSession(
      channel: channel,
      deviceExecutor: DeviceExecutor(
        capabilities: const DeviceCapabilities(
          platform: 'android',
          osVersion: '16',
          present: {},
        ),
        tools: [tool],
        scope: const AuthorizedScope.empty(),
      ),
      delay: (_) async {},
    );
  });

  group('replayed tool_call', () {
    test('runs the tool exactly once when the same call arrives twice',
        () async {
      session.applyFrame(_call('c1'));
      await _settle();
      // The server lost our result and replays the call.
      session.applyFrame(_call('c1'));
      await _settle();

      expect(tool.runs, 1, reason: 'a replay must not re-run the tool');
    });

    test('still answers the replay — silence would strand the run', () async {
      session.applyFrame(_call('c1'));
      await _settle();
      session.applyFrame(_call('c1'));
      await _settle();

      final results =
          channel.sent.whereType<DeviceToolResultMessage>().toList();
      expect(results.length, 2, reason: 'both calls get a result posted');
      expect(results.every((r) => r.callId == 'c1'), isTrue);
      expect(results[0].summary, results[1].summary,
          reason: 'the replay is answered from what already happened');
    });

    test('a replay while the call is still running does not double-run',
        () async {
      session.applyFrame(_call('c1'));
      // No settle: land the replay mid-flight, which is exactly what a
      // reconnect during a slow scan looks like.
      session.applyFrame(_call('c1'));
      await _settle();

      expect(tool.runs, 1);
    });

    test('different call ids are not confused for each other', () async {
      session.applyFrame(_call('c1'));
      session.applyFrame(_call('c2'));
      await _settle();

      expect(tool.runs, 2);
      final ids = channel.sent
          .whereType<DeviceToolResultMessage>()
          .map((r) => r.callId)
          .toSet();
      expect(ids, {'c1', 'c2'});
    });

    test('a replay long after the run still does not re-run', () async {
      session.applyFrame(_call('c1'));
      await _settle();
      await _settle();
      await _settle();
      session.applyFrame(_call('c1'));
      await _settle();

      expect(tool.runs, 1,
          reason: 'the guard is per session, not per run — a resume can '
              'replay a call from an earlier run');
    });
  });
}
