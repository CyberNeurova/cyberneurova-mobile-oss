import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How an install ended.
///
/// Mirrors `PackageInstaller`'s status codes, narrowed to what a user or an
/// agent can actually do something about.
enum InstallOutcome {
  /// Installed. The package is on the device now.
  success,

  /// The user tapped Cancel on the system dialog. Not an error — a decision,
  /// and an agent must not retry it as though it were a transient failure.
  declined,

  /// Rejected by the system: bad signature, downgrade, incompatible ABI.
  refused,

  /// We are not allowed to ask yet — "install unknown apps" is off.
  notPermitted,

  failed,
}

/// The result of asking to install.
class InstallResult {
  const InstallResult({
    required this.outcome,
    this.message,
  });

  final InstallOutcome outcome;
  final String? message;

  bool get ok => outcome == InstallOutcome.success;
}

/// Installing an APK that is already on this device.
///
/// ## Why this is worth having
///
/// A phone that can write code and cannot run it is a text editor. The gap
/// between "the agent produced an APK" and "the APK is on my phone" is the
/// whole point of doing this work on the device rather than on a laptop.
///
/// ## Every phone, not just rooted ones
///
/// `pm install` needs a privileged shell — root, our ADB bridge, or Shizuku —
/// and most phones have none. PackageInstaller needs none: the system shows
/// its own confirmation, the user taps Install, done. A privileged channel is
/// an optimisation that makes it silent, not the mechanism.
///
/// The user is never bypassed on this path, which is the right amount of power
/// for an agent to have over what gets installed on someone's phone.
class ApkInstall {
  const ApkInstall._();

  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('ai.cyberneurova.app/device_runtime');

  /// Completes when the system reports the outcome — after the user answers.
  static Completer<InstallResult>? _pending;

  static bool _listening = false;

  /// Whether Android will let us ask at all.
  static Future<bool> isAllowed() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('canInstallApks') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the one Settings screen that grants it.
  ///
  /// Written directions to "Settings › Apps › …" are where this loses people,
  /// the same way they got lost finding wireless debugging.
  static Future<bool> openPermissionSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('openInstallPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Installs the APK at [path].
  ///
  /// Resolves when the install finishes, which is **after the user answers the
  /// system dialog** — so this can take as long as they take. [timeout] exists
  /// only so a caller is never stuck forever on a dialog that was swiped away.
  static Future<InstallResult> install(
    String path, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const InstallResult(
        outcome: InstallOutcome.notPermitted,
        message: 'Installing apps is Android-only.',
      );
    }

    _listen();

    // One at a time. Two overlapping installs would race for the same
    // completer and report each other's outcome.
    final inFlight = _pending;
    if (inFlight != null && !inFlight.isCompleted) {
      return const InstallResult(
        outcome: InstallOutcome.failed,
        message: 'An install is already waiting for the user to confirm.',
      );
    }

    final completer = Completer<InstallResult>();
    _pending = completer;

    final Map<Object?, Object?>? started;
    try {
      started = await channel.invokeMapMethod<Object?, Object?>(
        'installApk',
        {'path': path},
      );
    } on PlatformException catch (e) {
      _pending = null;
      return InstallResult(
          outcome: InstallOutcome.failed, message: e.message);
    } on MissingPluginException {
      _pending = null;
      return const InstallResult(
        outcome: InstallOutcome.failed,
        message: 'This build has no installer.',
      );
    }

    if (started?['ok'] != true) {
      _pending = null;
      return InstallResult(
        outcome: started?['needsPermission'] == true
            ? InstallOutcome.notPermitted
            : InstallOutcome.failed,
        message: started?['error'] as String? ?? 'Could not start the install.',
      );
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending = null;
        return const InstallResult(
          outcome: InstallOutcome.failed,
          message: 'Timed out waiting for the install to be confirmed.',
        );
      },
    );
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onInstallResult') return null;
      final args = (call.arguments as Map).cast<Object?, Object?>();
      final result = InstallResult(
        outcome: outcomeFor(args['status'] as int?),
        message: args['message'] as String?,
      );
      final pending = _pending;
      _pending = null;
      if (pending != null && !pending.isCompleted) pending.complete(result);
      return null;
    });
  }

  /// Maps `PackageInstaller.STATUS_*` to something actionable.
  ///
  /// The distinction that matters is ABORTED: the user said no. An agent that
  /// reads that as a transient failure will helpfully ask again, which is how
  /// a refusal turns into nagging.
  @visibleForTesting
  static InstallOutcome outcomeFor(int? status) => switch (status) {
        0 => InstallOutcome.success, // STATUS_SUCCESS
        3 => InstallOutcome.declined, // STATUS_FAILURE_ABORTED
        2 => InstallOutcome.refused, // STATUS_FAILURE_BLOCKED
        4 => InstallOutcome.refused, // STATUS_FAILURE_INVALID
        5 => InstallOutcome.refused, // STATUS_FAILURE_CONFLICT
        6 => InstallOutcome.failed, // STATUS_FAILURE_STORAGE
        7 => InstallOutcome.refused, // STATUS_FAILURE_INCOMPATIBLE
        _ => InstallOutcome.failed,
      };
}
