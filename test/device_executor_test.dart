import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_session.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/network_tools.dart';

class RecordingChannel implements AgentControlChannel {
  final List<AgentControlMessage> sent = [];
  @override
  bool get isConnected => true;
  @override
  Future<void> send(AgentControlMessage message) async => sent.add(message);
}

/// A tool with no side effects, so executor behaviour can be tested without
/// touching a real network.
class EchoTool implements DeviceTool {
  EchoTool({
    this.toolName = 'echo',
    this.needs = const {},
    this.targetKey,
    this.isRange = false,
  });

  final String toolName;
  final Set<DeviceCapability> needs;
  final String? targetKey;
  final bool isRange;

  bool ran = false;

  @override
  String get name => toolName;
  @override
  Set<DeviceCapability> get requires => needs;
  @override
  String? get targetArgKey => targetKey;
  @override
  bool targetIsRange(Map<String, dynamic> args) => isRange;

  @override
  Future<DeviceToolResult> run(
      Map<String, dynamic> args, DeviceToolContext context) async {
    ran = true;
    context.onProgress('working');
    return DeviceToolResult(ok: true, summary: 'echoed ${args['value']}');
  }
}

DeviceCapabilities _caps({Set<DeviceCapability>? present}) =>
    DeviceCapabilities(
      platform: 'ios',
      osVersion: '26.5',
      present: present ?? DeviceCapabilities.pureDartBaseline,
    );

void main() {
  group('AuthorizedScope', () {
    test('empty scope still allows the device itself', () {
      const scope = AuthorizedScope.empty();
      expect(scope.check('localhost').isAllowed, isTrue);
      expect(scope.check('127.0.0.1').isAllowed, isTrue);
      // But nothing else — this is the safe default.
      expect(scope.check('192.168.1.5').isAllowed, isFalse);
    });

    test('CIDR membership', () {
      const scope = AuthorizedScope(cidrs: ['192.168.1.0/24']);
      expect(scope.check('192.168.1.7').isAllowed, isTrue);
      expect(scope.check('192.168.2.7').isAllowed, isFalse);
    });

    test('wildcard hostnames match subdomains but not the bare domain', () {
      const scope = AuthorizedScope(hostPatterns: ['*.lab.example.com']);
      expect(scope.check('box.lab.example.com').isAllowed, isTrue);
      expect(scope.check('lab.example.com').isAllowed, isFalse);
      expect(scope.check('evil.com').isAllowed, isFalse);
    });

    test('local subnet resolves at call time, not capture time', () {
      const scope = AuthorizedScope(includeLocalSubnet: true);
      // On this network: allowed.
      expect(
        scope.check('10.0.0.5', localSubnetCidrs: ['10.0.0.0/24']).isAllowed,
        isTrue,
      );
      // Moved to a different network: the old host is no longer authorised.
      expect(
        scope.check('10.0.0.5', localSubnetCidrs: ['192.168.4.0/24']).isAllowed,
        isFalse,
      );
    });

    test('a range is in scope only when fully contained', () {
      const scope = AuthorizedScope(cidrs: ['192.168.1.0/24']);
      expect(scope.checkRange('192.168.1.0/24').isAllowed, isTrue);
      expect(scope.checkRange('192.168.1.0/25').isAllowed, isTrue);
      // Wider than what was authorised — must be refused, even though it
      // overlaps.
      expect(scope.checkRange('192.168.0.0/16').isAllowed, isFalse);
    });
  });

  group('DeviceExecutor', () {
    test('runs a registered tool', () async {
      final tool = EchoTool();
      final ex = DeviceExecutor(capabilities: _caps(), tools: [tool]);

      final r = await ex.execute(
          callId: 'c1', tool: 'echo', args: {'value': 'hi'});

      expect(tool.ran, isTrue);
      expect(r.ok, isTrue);
      expect(r.summary, 'echoed hi');
    });

    test('refuses an unknown tool with a usable message', () async {
      final ex = DeviceExecutor(capabilities: _caps(), tools: [EchoTool()]);
      final r = await ex.execute(callId: 'c1', tool: 'nope', args: {});

      expect(r.ok, isFalse);
      // The model should learn what IS available rather than retrying.
      expect(r.error, contains('echo'));
    });

    test('refuses when a capability is missing, and names it', () async {
      final tool = EchoTool(needs: {DeviceCapability.rawSocket});
      final ex = DeviceExecutor(capabilities: _caps(), tools: [tool]);

      final r = await ex.execute(callId: 'c1', tool: 'echo', args: {});

      expect(tool.ran, isFalse);
      expect(r.error, contains('RAW_SOCKET'));
      // Naming the limitation is what lets the agent pick another technique.
      expect(r.error, contains('another technique'));
    });

    test('refuses an out-of-scope target before running anything', () async {
      final tool = EchoTool(targetKey: 'target');
      final ex = DeviceExecutor(
        capabilities: _caps(),
        tools: [tool],
        scope: const AuthorizedScope(cidrs: ['192.168.1.0/24']),
      );

      final r = await ex.execute(
          callId: 'c1', tool: 'echo', args: {'target': '8.8.8.8'});

      expect(tool.ran, isFalse, reason: 'must not execute out of scope');
      expect(r.ok, isFalse);
      expect(r.error, contains('outside the authorized scope'));
    });

    test('allows an in-scope target', () async {
      final tool = EchoTool(targetKey: 'target');
      final ex = DeviceExecutor(
        capabilities: _caps(),
        tools: [tool],
        scope: const AuthorizedScope(cidrs: ['192.168.1.0/24']),
      );

      final r = await ex.execute(
          callId: 'c1', tool: 'echo', args: {'target': '192.168.1.9'});

      expect(tool.ran, isTrue);
      expect(r.ok, isTrue);
    });

    test('a thrown tool becomes a failure, not a crash', () async {
      final ex = DeviceExecutor(capabilities: _caps(), tools: [_ThrowingTool()]);
      final r = await ex.execute(callId: 'c1', tool: 'boom', args: {});
      expect(r.ok, isFalse);
      expect(r.error, contains('boom failed'));
    });

    test('a hung tool is timed out', () async {
      final ex = DeviceExecutor(
        capabilities: _caps(),
        tools: [_HangingTool()],
        defaultTimeout: const Duration(milliseconds: 40),
      );
      final r = await ex.execute(callId: 'c1', tool: 'hang', args: {});
      expect(r.ok, isFalse);
      expect(r.error, contains('timed out'));
    });
  });

  group('capability block', () {
    test('lists present and missing, and the resolved scope', () {
      final caps = _caps();
      final block = caps.promptBlock(
        scope: const AuthorizedScope(includeLocalSubnet: true),
        localSubnetCidrs: ['192.168.1.0/24'],
        cwd: '/workspaces/s1',
      );

      expect(block, contains('EXECUTOR: device (ios 26.5)'));
      expect(block, contains('TCP_CONNECT'));
      // The whole point: the model must know what it CANNOT do, or it
      // proposes nmap -sS and loops on the failure.
      expect(block, contains('MISSING:'));
      expect(block, contains('RAW_SOCKET'));
      expect(block, contains('AUTHORIZED SCOPE: 192.168.1.0/24'));
      expect(block, contains('CWD: /workspaces/s1'));
    });

    test('says the hardware is real before it says anything else', () {
      final block = _caps().promptBlock(scope: const AuthorizedScope.empty());

      // Measured failure, 2026-08-03: given only a heading and a capability
      // list, the model opened with "You are currently operating within a
      // simulated environment" and then printed the user's real device
      // fingerprint underneath. A model that believes it is sandboxed
      // narrates commands instead of running them.
      expect(block, startsWith('THIS IS REAL HARDWARE.'));
      expect(block, contains('physical phone'));
      // Consequences, not adjectives — this is the part that changes what
      // the model does.
      expect(block, contains('still there tomorrow'));
      expect(block, contains('Never describe a command as though you had run'));
    });

    test('empty scope reads as device-only', () {
      final block = _caps().promptBlock(scope: const AuthorizedScope.empty());
      expect(block, contains('AUTHORIZED SCOPE: this device only'));
    });

    test('hands the model the device IP so it need not shell out for it', () {
      // The reported failure: "what's my local ip" in an Alpine PRoot console
      // produced 14 failing shell_exec calls (hostname -I, ip addr show, …) and
      // no answer, because the shell cannot read the network namespace under
      // PRoot. The address is a fact the app already has — state it.
      final block = _caps().promptBlock(
        scope: const AuthorizedScope.empty(),
        selfIps: ['192.168.100.8'],
        localSubnetCidrs: ['192.168.100.0/24'],
      );
      expect(block, contains("THIS DEVICE'S IP: 192.168.100.8"));
      expect(block, contains('192.168.100.0/24'));
      // And it must be told NOT to go looking for it in the shell.
      expect(block, contains('do not run a shell command to discover it'));
    });

    // The BASE-TOOLS line is Android-shell-specific, so these two use an
    // android executor rather than the ios [_caps].
    DeviceCapabilities androidCaps() => DeviceCapabilities(
          platform: 'android',
          osVersion: '14',
          present: DeviceCapabilities.pureDartBaseline,
        );

    test('under PRoot, says it is a guest shell without false tool claims', () {
      // The block must tell the model it is a PRoot guest, not Android's shell,
      // and point at the IP line. It must NOT assert that network tools fail —
      // an earlier draft did, and it was false: `ifconfig` succeeded on device.
      final proot = androidCaps().promptBlock(
        scope: const AuthorizedScope.empty(),
        underProot: true,
      );
      expect(proot, contains('PRoot Linux guest'));
      expect(proot, contains('use the IP line above'));
      // No false blanket claim that the network tools return nothing.
      expect(proot, isNot(contains('does NOT work')));
      expect(proot, isNot(contains('return nothing')));
      // And it must NOT claim the Android toybox base tools inside a distro.
      expect(proot, isNot(contains('BASE TOOLS: /system/bin/sh')));
    });

    test('the bare Android shell still advertises its toybox base tools', () {
      // The non-distro case must be unchanged — a fresh install is not "no
      // tools", and saying so is what stopped the model refusing work it could
      // do.
      final android = androidCaps().promptBlock(
        scope: const AuthorizedScope.empty(),
        underProot: false,
      );
      expect(android, contains('BASE TOOLS: /system/bin/sh'));
    });
  });

  group('AgentSession device execution', () {
    test('executes a device-tagged call and posts the result back', () async {
      final channel = RecordingChannel();
      final tool = EchoTool();
      final session = AgentSession(
        channel: channel,
        deviceExecutor:
            DeviceExecutor(capabilities: _caps(), tools: [tool]),
        delay: (_) async {},
      );

      session.applyFrame(const AgentToolCall(
        callId: 'c1',
        tool: 'echo',
        input: {'value': 'x'},
        executor: 'device',
      ));
      await _settle();

      expect(tool.ran, isTrue, reason: 'work happens on the device');

      // Result reflected locally without waiting for a server round-trip.
      final card = session.transcript.items.single as ToolCardItem;
      expect(card.state, ToolCardState.succeeded);
      expect(card.summary, 'echoed x');

      final msg = channel.sent
          .whereType<DeviceToolResultMessage>()
          .single;
      expect(msg.callId, 'c1');
      expect(msg.ok, isTrue);
      expect(msg.toJson()['type'], 'device_tool_result');
    });

    test('a server-executed call is rendered but not run locally', () async {
      final channel = RecordingChannel();
      final tool = EchoTool();
      final session = AgentSession(
        channel: channel,
        deviceExecutor:
            DeviceExecutor(capabilities: _caps(), tools: [tool]),
        delay: (_) async {},
      );

      session.applyFrame(const AgentToolCall(
        callId: 'c1',
        tool: 'echo',
        input: {},
        // Default executor — the server's job.
      ));
      await _settle();

      expect(tool.ran, isFalse);
      expect(channel.sent.whereType<DeviceToolResultMessage>(), isEmpty);
    });

    test('an out-of-scope device call reports refusal upstream', () async {
      final channel = RecordingChannel();
      final tool = EchoTool(targetKey: 'target');
      final session = AgentSession(
        channel: channel,
        deviceExecutor: DeviceExecutor(
          capabilities: _caps(),
          tools: [tool],
          scope: const AuthorizedScope(cidrs: ['10.0.0.0/24']),
        ),
        delay: (_) async {},
      );

      session.applyFrame(const AgentToolCall(
        callId: 'c1',
        tool: 'echo',
        input: {'target': '8.8.8.8'},
        executor: 'device',
      ));
      await _settle();

      expect(tool.ran, isFalse);
      final msg = channel.sent.whereType<DeviceToolResultMessage>().single;
      expect(msg.ok, isFalse);
      // The agent is told why, so it can ask the user to widen scope rather
      // than silently retrying.
      expect(msg.error, contains('outside the authorized scope'));
    });

    test('cancel stops local work immediately', () async {
      final channel = RecordingChannel();
      final executor =
          DeviceExecutor(capabilities: _caps(), tools: [EchoTool()]);
      final session = AgentSession(
        channel: channel,
        deviceExecutor: executor,
        delay: (_) async {},
      );

      session.cancel(callId: 'c1');
      await _settle();

      // Both: local stop, and a cancel sent so the server stops too.
      expect(channel.sent.whereType<CancelMessage>(), hasLength(1));
    });

    test('frames parse the executor field', () {
      final frame = AgentFrame.tryParse({
        'type': 'tool_call',
        'call_id': 'c1',
        'tool': 'net_scan',
        'executor': 'device',
        'input': {'target': '192.168.1.1'},
      }) as AgentToolCall;

      expect(frame.runsOnDevice, isTrue);

      final serverSide = AgentFrame.tryParse({
        'type': 'tool_call',
        'call_id': 'c2',
        'tool': 'WebSearch',
        'input': {},
      }) as AgentToolCall;
      expect(serverSide.runsOnDevice, isFalse);
    });
  });

  _wiringTests();
  _gateTests();
}

class _ThrowingTool implements DeviceTool {
  @override
  String get name => 'boom';
  @override
  Set<DeviceCapability> get requires => const {};
  @override
  String? get targetArgKey => null;
  @override
  bool targetIsRange(Map<String, dynamic> args) => false;
  @override
  Future<DeviceToolResult> run(
          Map<String, dynamic> args, DeviceToolContext context) async =>
      throw StateError('nope');
}

class _HangingTool implements DeviceTool {
  @override
  String get name => 'hang';
  @override
  Set<DeviceCapability> get requires => const {};
  @override
  String? get targetArgKey => null;
  @override
  bool targetIsRange(Map<String, dynamic> args) => false;
  @override
  Future<DeviceToolResult> run(
      Map<String, dynamic> args, DeviceToolContext context) async {
    await Future<void>.delayed(const Duration(seconds: 30));
    return const DeviceToolResult(ok: true);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ─── Wiring: the executor as the app actually constructs it ─────────────────

void _wiringTests() {
  group('as-wired executor', () {
    test('registers the three device tools', () {
      final ex = DeviceExecutor(
        capabilities: _caps(),
        tools: [NetDiscoverTool(), NetScanTool(), DnsQueryTool()],
      );
      expect(ex.toolNames, containsAll(['net_discover', 'net_scan', 'dns_query']));
    });

    test('with an empty scope, LAN work is refused but localhost is not',
        () async {
      final ex = DeviceExecutor(
        capabilities: _caps(),
        tools: [NetScanTool()],
        // The shipped default.
        scope: const AuthorizedScope.empty(),
      );

      final lan = await ex.execute(
          callId: 'c1', tool: 'net_scan', args: {'target': '192.168.1.1'});
      expect(lan.ok, isFalse);
      expect(lan.error, contains('outside the authorized scope'));

      // Declaring scope is what unlocks it — nothing else.
      ex.scope = const AuthorizedScope(includeLocalSubnet: true);
      ex.localSubnetCidrs = ['192.168.1.0/24'];
      final allowed = await ex.execute(
        callId: 'c2',
        tool: 'net_scan',
        args: {'target': '192.168.1.1', 'ports': '1', 'timeout_ms': 1},
      );
      // Reaches the tool: no scope error, whatever the scan itself found.
      expect(allowed.error, isNot(contains('scope')));
    });

    test('net_discover refuses a range wider than the declared scope',
        () async {
      final ex = DeviceExecutor(
        capabilities: _caps(),
        tools: [NetDiscoverTool()],
        scope: const AuthorizedScope(cidrs: ['192.168.1.0/24']),
      );
      final r = await ex.execute(
          callId: 'c1', tool: 'net_discover', args: {'target': '192.168.0.0/16'});
      expect(r.ok, isFalse);
      expect(r.error, contains('outside the authorized scope'));
    });
  });
}

// ─── The gate: device tools are Shell-only ─────────────────────────────────

void _gateTests() {
  group('device-tool gate', () {
    test('a session with no executor refuses and says why', () async {
      final channel = RecordingChannel();
      // deviceExecutor omitted — what an ordinary chat, Code or Research
      // session gets.
      final session = AgentSession(channel: channel, delay: (_) async {});

      session.applyFrame(const AgentToolCall(
        callId: 'c1',
        tool: 'net_scan',
        input: {'target': '192.168.1.1'},
        executor: 'device',
      ));
      await _settle();

      final msg = channel.sent.whereType<DeviceToolResultMessage>().single;
      expect(msg.ok, isFalse);
      // The agent should learn the constraint, not retry blindly.
      expect(msg.error, contains('Shell sessions'));
    });

    test('a Shell session with an executor runs it', () async {
      final channel = RecordingChannel();
      final tool = EchoTool();
      final session = AgentSession(
        channel: channel,
        deviceExecutor: DeviceExecutor(capabilities: _caps(), tools: [tool]),
        delay: (_) async {},
      );

      session.applyFrame(const AgentToolCall(
        callId: 'c1',
        tool: 'echo',
        input: {},
        executor: 'device',
      ));
      await _settle();

      expect(tool.ran, isTrue);
      expect(
          channel.sent.whereType<DeviceToolResultMessage>().single.ok, isTrue);
    });
  });
}
