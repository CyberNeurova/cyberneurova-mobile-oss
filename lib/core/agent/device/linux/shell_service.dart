import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether we can reach the ADB shell uid, and how far along the user is.
///
/// Deliberately more than a bool: each state needs different words. "Install
/// Shizuku" and "you already have it, just tap allow" are not the same
/// message, and collapsing them produces the kind of instruction that sends
/// people in circles.
enum ShellServiceStatus {
  /// No Shizuku, or its service is not running. The common case, and not an
  /// error — everything works without it, with fewer capabilities.
  unavailable,

  /// Service is running; we have not been granted access yet.
  present,

  /// The user refused. Distinct from [present] because it means asking again
  /// is a repeat request, not a first one.
  denied,

  /// Granted. Commands run at the service's uid.
  granted,

  /// A Shizuku too old for the current API. Nothing to do but say so.
  unsupported,
}

/// Result of a command run through the service.
class ShellServiceResult {
  const ShellServiceResult({
    required this.ok,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final bool ok;
  final int exitCode;
  final String stdout;
  final String stderr;

  static const failed = ShellServiceResult(
    ok: false,
    exitCode: -1,
    stdout: '',
    stderr: 'The shell service is not available.',
  );
}

/// The ADB shell uid (2000), reached through Shizuku.
///
/// ## What this is for
///
/// Our app prompts for everything. The shell uid does not: it holds
/// `INSTALL_PACKAGES`, `DELETE_PACKAGES`, `GRANT_RUNTIME_PERMISSIONS`,
/// `WRITE_SECURE_SETTINGS`, `READ_LOGS` and `DUMP`, and can enumerate every
/// installed package without `QUERY_ALL_PACKAGES`. Measured on hardware, see
/// `docs/shell/16-CAPABILITY-ROADMAP.md` §2.2.
///
/// The user reaches it with **no root and no computer** — Android 11+ pairs
/// wireless debugging on-device and Shizuku turns that into a bindable
/// service.
///
/// ## What it is not
///
/// Not root. Shell's `CapEff` is zero, so raw sockets, packet capture and
/// monitor mode remain unavailable. Anything that needs `CAP_NET_RAW` still
/// needs [RootAccess].
///
/// ## The lifecycle trap
///
/// **The service dies on every reboot** and the user must re-pair. So this is
/// never cached across sessions: [status] is asked fresh, and a feature built
/// on it has to degrade the moment it goes away rather than assume it will
/// still be there.
class ShellService {
  const ShellService._();

  static const MethodChannel _channel =
      MethodChannel('ai.cyberneurova.app/device_runtime');

  /// `defaultTargetPlatform` rather than `Platform.isAndroid`: dart:io cannot
  /// be overridden under test, so the io check made every path below
  /// unreachable from a test and the mapping went unverified.
  static bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Current state. Cheap; call it rather than remembering the answer.
  static Future<ShellServiceStatus> status() async {
    if (!_isAndroid) return ShellServiceStatus.unavailable;
    try {
      final s = await _channel.invokeMethod<String>('shizukuStatus');
      return switch (s) {
        'granted' => ShellServiceStatus.granted,
        'present' => ShellServiceStatus.present,
        'denied' => ShellServiceStatus.denied,
        'unsupported' => ShellServiceStatus.unsupported,
        _ => ShellServiceStatus.unavailable,
      };
    } on PlatformException {
      return ShellServiceStatus.unavailable;
    } on MissingPluginException {
      return ShellServiceStatus.unavailable;
    }
  }

  /// Posts the pairing prompt whose inline reply does the pairing.
  ///
  /// The notification shade is the only input surface that survives the
  /// system pairing dialog: switching to our app closes that dialog, and
  /// overlays are force-hidden over it. Pulling the shade down pauses Settings
  /// without destroying it, so the dialog and its pairing service stay alive
  /// — verified on device, the code was identical before and after.
  static Future<bool> showPairingNotification() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('showPairingNotification') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> dismissPairingNotification() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('dismissPairingNotification');
    } on PlatformException {
      // Nothing posted.
    } on MissingPluginException {
      // Older build.
    }
  }

  /// Opens Developer options, where the pairing code lives.
  ///
  /// Written directions to "find Developer options" are where this flow loses
  /// people, so we take them there.
  static Future<bool> openWirelessDebuggingSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openWirelessDebugging') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The uid the service runs as: 2000 over ADB, 0 if the user started it
  /// with root. Worth surfacing — a root-started service can do strictly more,
  /// and the difference is invisible otherwise.
  static Future<int> serviceUid() async {
    if (!_isAndroid) return -1;
    try {
      return await _channel.invokeMethod<int>('shizukuUid') ?? -1;
    } on PlatformException {
      return -1;
    } on MissingPluginException {
      return -1;
    }
  }

  /// Asks the user for access. Shows Shizuku's dialog; resolves with their
  /// answer rather than returning immediately, so callers can await it.
  static Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('shizukuRequestPermission') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Runs [command] through `sh -c` at the service's uid.
  ///
  /// Never throws — a failure comes back as a result with `ok: false` and a
  /// reason, because every caller here is on a path where "it did not work"
  /// is an ordinary outcome to report, not an exception to unwind.
  static Future<ShellServiceResult> exec(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAndroid) return ShellServiceResult.failed;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'shizukuExec',
        {'command': command, 'timeoutMs': timeout.inMilliseconds},
      );
      if (r == null) return ShellServiceResult.failed;
      return ShellServiceResult(
        ok: r['ok'] as bool? ?? false,
        exitCode: r['exitCode'] as int? ?? -1,
        stdout: r['stdout'] as String? ?? '',
        stderr: r['stderr'] as String? ?? '',
      );
    } on PlatformException catch (e) {
      return ShellServiceResult(
        ok: false,
        exitCode: -1,
        stdout: '',
        stderr: e.message ?? 'Platform error',
      );
    } on MissingPluginException {
      return ShellServiceResult.failed;
    }
  }
}

/// Pairing with the phone's own wireless debugging, in-app.
///
/// The same uid-2000 access [ShellService] describes, reached without
/// installing anything: Android 11+ runs wireless debugging on the device
/// itself, so the phone pairs with itself over loopback. Nothing crosses the
/// network.
///
/// Kept beside Shizuku rather than replacing it — whichever channel is
/// available wins, and a user who already runs Shizuku never has to care that
/// this exists.
class AdbPairing {
  const AdbPairing._();

  static const MethodChannel _channel =
      MethodChannel('ai.cyberneurova.app/device_runtime');

  static bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Pairs with the six-digit code.
  ///
  /// [port] must be the port from **inside the pairing dialog**, not the one
  /// on the wireless debugging screen behind it. They differ, and confusing
  /// them is the most common way this fails — the UI has to say which.
  static Future<({bool ok, String? error})> pair({
    required int port,
    required String code,
  }) async {
    if (!_isAndroid) return (ok: false, error: 'Android only.');
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'adbPair',
        {'port': port, 'code': code},
      );
      return (
        ok: r?['ok'] as bool? ?? false,
        error: r?['error'] as String?,
      );
    } on PlatformException catch (e) {
      return (ok: false, error: e.message);
    } on MissingPluginException {
      return (ok: false, error: 'Not available in this build.');
    }
  }

  /// Finds the pairing port over mDNS.
  ///
  /// Android advertises `_adb-tls-pairing._tcp` while the pairing dialog is
  /// open. Discovering it means the user only carries the six digits — the
  /// port is the worse half to ask for, because it changes every time the
  /// dialog reopens.
  static Future<({bool ok, int port, String? error})> discoverPairingPort({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!_isAndroid) return (ok: false, port: -1, error: 'Android only.');
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'adbDiscoverPairingPort',
        {'timeoutMs': timeout.inMilliseconds},
      );
      return (
        ok: r?['ok'] as bool? ?? false,
        port: r?['port'] as int? ?? -1,
        error: r?['error'] as String?,
      );
    } on PlatformException catch (e) {
      return (ok: false, port: -1, error: e.message);
    } on MissingPluginException {
      return (ok: false, port: -1, error: 'Not available in this build.');
    }
  }

  /// Whether wireless debugging is switched on right now, or null if this
  /// device will not say.
  ///
  /// Worth asking before [connect]: Android clears the toggle on every reboot,
  /// so "off" is the usual reason a connect fails. Discovery cannot tell that
  /// apart from a slow network — it just browses for ten seconds and comes
  /// back empty — and a screen that has to guess ends up saying nothing.
  static Future<bool?> isWirelessDebuggingOn() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('adbWirelessEnabled');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Connects, discovering the port over mDNS.
  ///
  /// Expected to fail routinely: wireless debugging switches itself off, and
  /// its port changes every time it comes back. `needsPairing` distinguishes
  /// "turn it on" from "pair first", which are different instructions.
  static Future<({bool ok, bool needsPairing, String? error})> connect({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_isAndroid) {
      return (ok: false, needsPairing: false, error: 'Android only.');
    }
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'adbConnect',
        {'timeoutMs': timeout.inMilliseconds},
      );
      return (
        ok: r?['ok'] as bool? ?? false,
        needsPairing: r?['needsPairing'] as bool? ?? false,
        error: r?['error'] as String?,
      );
    } on PlatformException catch (e) {
      return (ok: false, needsPairing: false, error: e.message);
    } on MissingPluginException {
      return (ok: false, needsPairing: false, error: 'Not available.');
    }
  }

  /// Whether this device has ever been paired.
  ///
  /// Distinct from [isConnected]: the pairing is a key on disk and survives
  /// reboots, app updates and the wireless-debugging toggle. The connection is
  /// a socket and does not. Conflating them is why a reconnect can look like a
  /// lost pairing.
  static Future<bool> isPaired() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('adbIsPaired') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isConnected() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('adbIsConnected') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// What we are connected to — device and privilege, not just a bool.
  ///
  /// "Connected" alone is not reassuring for something that can install apps
  /// without asking. Naming the device and the uid lets the user check it is
  /// what they think it is.
  static Future<({bool connected, String? device, String? uid})>
      connectionInfo() async {
    if (!_isAndroid) return (connected: false, device: null, uid: null);
    try {
      final r =
          await _channel.invokeMapMethod<String, dynamic>('adbConnectionInfo');
      return (
        connected: r?['connected'] as bool? ?? false,
        device: r?['device'] as String?,
        uid: r?['uid'] as String?,
      );
    } on PlatformException {
      return (connected: false, device: null, uid: null);
    } on MissingPluginException {
      return (connected: false, device: null, uid: null);
    }
  }

  static Future<void> disconnect() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('adbDisconnect');
    } on PlatformException {
      // Nothing to disconnect is not a failure.
    } on MissingPluginException {
      // Older build without the channel.
    }
  }

  /// Runs [command] at uid 2000.
  ///
  /// The ADB shell service carries no exit status, so `exitCode` is 0 whenever
  /// the command ran at all. Callers that need one append `; echo $?` and read
  /// the last line — inventing a status we do not have would be worse.
  static Future<ShellServiceResult> exec(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAndroid) return ShellServiceResult.failed;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'adbExec',
        {'command': command, 'timeoutMs': timeout.inMilliseconds},
      );
      if (r == null) return ShellServiceResult.failed;
      return ShellServiceResult(
        ok: r['ok'] as bool? ?? false,
        exitCode: r['exitCode'] as int? ?? -1,
        stdout: r['stdout'] as String? ?? '',
        stderr: r['stderr'] as String? ?? '',
      );
    } on PlatformException catch (e) {
      return ShellServiceResult(
        ok: false,
        exitCode: -1,
        stdout: '',
        stderr: e.message ?? 'Platform error',
      );
    } on MissingPluginException {
      return ShellServiceResult.failed;
    }
  }
}
