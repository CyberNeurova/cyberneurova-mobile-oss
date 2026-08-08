import 'dart:async';

import 'package:cyberneurova_mobile/core/agent/device/background_runs.dart';
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';

/// Outcome of running a tool on the device.
class DeviceToolResult {
  const DeviceToolResult({
    required this.ok,
    this.summary,
    this.output,
    this.error,
    this.artifacts = const [],
  });

  const DeviceToolResult.failure(String this.error)
      : ok = false,
        summary = null,
        output = null,
        artifacts = const [];

  final bool ok;

  /// The one line the card collapses to. Always worth setting — without it
  /// a finished card says "Port scan" instead of "3 of 1000 ports open".
  final String? summary;
  final String? output;
  final String? error;
  final List<Map<String, dynamic>> artifacts;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (summary != null) 'summary': summary,
        if (output != null) 'output': output,
        if (error != null) 'error': error,
        if (artifacts.isNotEmpty) 'artifacts': artifacts,
      };
}

/// A tool that runs on the phone rather than the server.
///
/// This is the point of the whole device-executor path: the VPS orchestrates
/// (cheap — mostly waiting on the model) while the actual work happens here.
/// It is also the only way to reach the user's LAN, which a container never
/// can.
abstract class DeviceTool {
  /// Wire name the server dispatches on.
  String get name;

  /// Capabilities this tool needs. If any are missing the executor refuses
  /// with an actionable reason instead of failing obscurely at runtime.
  Set<DeviceCapability> get requires;

  /// Argument key holding the thing packets get sent at, if any. Checked
  /// against the session scope before execution.
  String? get targetArgKey => null;

  /// True when the target names a range rather than a single host, so scope
  /// containment is checked instead of membership. Defaults to false.
  bool targetIsRange(Map<String, dynamic> args);

  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  );
}

/// Everything a device tool is allowed to know about its session.
class DeviceToolContext {
  DeviceToolContext({
    required this.capabilities,
    required this.scope,
    required this.localSubnetCidrs,
    required this.onProgress,
    required this.isCancelled,
  });

  final DeviceCapabilities capabilities;
  final AuthorizedScope scope;
  final List<String> localSubnetCidrs;

  /// Streams a line back to the run so the card shows motion.
  final void Function(String line) onProgress;

  /// Long-running tools must poll this and stop promptly — the user can tap
  /// Stop, and a scan that ignores it is worse than one that never started.
  final bool Function() isCancelled;
}

/// Dispatches server-issued device tool calls to registered tools.
///
/// Enforces three things before any tool runs, in this order:
///
/// 1. **The tool exists.** Unknown tools get a clear refusal, so the model
///    learns rather than retrying.
/// 2. **Capabilities are present.** Refusing early with a named missing
///    capability is what lets the agent pick a different technique.
/// 3. **The target is in scope.** The server checks too and its verdict is
///    authoritative, but the device re-checks so a replayed or tampered
///    frame cannot point the phone at an unauthorised host.
class DeviceExecutor {
  DeviceExecutor({
    required this.capabilities,
    required List<DeviceTool> tools,
    this.scope = const AuthorizedScope.empty(),
    this.localSubnetCidrs = const [],
    this.defaultTimeout = const Duration(seconds: 60),
  }) : _tools = {for (final t in tools) t.name: t};

  final DeviceCapabilities capabilities;
  final Map<String, DeviceTool> _tools;
  AuthorizedScope scope;
  List<String> localSubnetCidrs;
  final Duration defaultTimeout;

  final Map<String, bool> _cancelled = {};

  Iterable<String> get toolNames => _tools.keys;

  bool canHandle(String tool) => _tools.containsKey(tool);

  /// Marks a call cancelled. Running tools observe this through
  /// [DeviceToolContext.isCancelled].
  void cancel(String callId) => _cancelled[callId] = true;

  Future<DeviceToolResult> execute({
    required String callId,
    required String tool,
    required Map<String, dynamic> args,
    void Function(String line)? onProgress,
    Duration? timeout,
  }) async {
    final impl = _tools[tool];
    if (impl == null) {
      return DeviceToolResult.failure(
        'This device has no tool named "$tool". Available: '
        '${_tools.keys.join(', ')}.',
      );
    }

    final missing = impl.requires.difference(capabilities.present);
    if (missing.isNotEmpty) {
      return DeviceToolResult.failure(
        'This device cannot run $tool — missing '
        '${[for (final c in missing) c.wireName].join(', ')}. '
        'Route it to a remote executor or choose another technique.',
      );
    }

    final targetKey = impl.targetArgKey;
    if (targetKey != null) {
      final target = args[targetKey];
      if (target is! String || target.trim().isEmpty) {
        return DeviceToolResult.failure(
            '$tool needs a "$targetKey" argument.');
      }
      final verdict = impl.targetIsRange(args)
          ? scope.checkRange(target, localSubnetCidrs: localSubnetCidrs)
          : scope.check(target, localSubnetCidrs: localSubnetCidrs);
      if (!verdict.isAllowed) {
        return DeviceToolResult.failure(
          '${verdict.reason} Update the session scope first — I will not '
          'work around it.',
        );
      }
    }

    _cancelled.remove(callId);
    final context = DeviceToolContext(
      capabilities: capabilities,
      scope: scope,
      localSubnetCidrs: localSubnetCidrs,
      onProgress: onProgress ?? (_) {},
      isCancelled: () => _cancelled[callId] == true,
    );

    // A tool call is work running ON this device, so it is the one place that
    // genuinely earns a wake lock — the screen going off during a scan or an
    // install must not stall it. Released in the finally below, always.
    final guard = BackgroundRuns.instance.beginRun(tool, true);

    try {
      return await impl
          .run(args, context)
          .timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      return DeviceToolResult.failure(
        '$tool timed out after ${(timeout ?? defaultTimeout).inSeconds}s.',
      );
    } catch (e) {
      return DeviceToolResult.failure('$tool failed: $e');
    } finally {
      guard.end();
      _cancelled.remove(callId);
    }
  }
}
