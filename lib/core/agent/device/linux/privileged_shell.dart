import 'package:cyberneurova_mobile/core/agent/device/linux/root_access.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_service.dart';

/// How we are running privileged commands, if at all.
///
/// Ordered by capability, most capable first — [best] relies on that order.
enum PrivilegeChannel {
  /// `su`. Everything the shell uid can do, plus the kernel capabilities it
  /// cannot: raw sockets, packet capture, monitor mode.
  root,

  /// Our own ADB pairing over the phone's wireless debugging. uid 2000.
  adb,

  /// Shizuku's service, if the user already runs it. Also uid 2000, or 0 when
  /// they started it with root.
  shizuku,

  /// Nothing privileged. Everything still works, with prompts and without
  /// package management.
  none,
}

/// One privileged shell, whichever way we can get it.
///
/// ## Why this exists
///
/// There are three ways to reach a privileged shell on Android and callers
/// should not care which one they got. Without this, every feature that wants
/// to install a package grows its own if/else over root, ADB and Shizuku, and
/// they drift.
///
/// ## The ordering is the point
///
/// **Root wins, and a rooted device is never asked to pair over ADB.** That
/// was the owner's instruction and it is also just correct: `su` is a superset
/// of uid 2000, so sending a rooted user through wireless debugging would cost
/// them a setup flow to obtain less than they already have.
///
/// Only [root] carries kernel capabilities. Shell uid's `CapEff` is zero —
/// measured, not assumed — so raw sockets stay root-only regardless of how
/// convenient ADB is for everything else.
class PrivilegedShell {
  const PrivilegedShell._();

  /// The best channel currently available, and the root grant behind it.
  ///
  /// Does not prompt: [RootAccess.detect] only looks for the binary, and the
  /// ADB/Shizuku checks are passive. Asking for privileges the user has not
  /// requested is how apps train people to tap Deny.
  static Future<({PrivilegeChannel channel, RootAccess root})> best({
    RootAccess? grantedRoot,
  }) async {
    // A root grant the user has already given beats everything, and beats it
    // without a single dialog.
    if (grantedRoot != null && grantedRoot.isUsable) {
      return (channel: PrivilegeChannel.root, root: grantedRoot);
    }

    final detected = await RootAccess.detect();

    if (await AdbPairing.isConnected()) {
      return (channel: PrivilegeChannel.adb, root: detected);
    }
    if (await ShellService.status() == ShellServiceStatus.granted) {
      return (channel: PrivilegeChannel.shizuku, root: detected);
    }
    return (channel: PrivilegeChannel.none, root: detected);
  }

  /// Runs [command] on the best available channel.
  ///
  /// Never throws. A missing channel is an ordinary result with a reason,
  /// because "we have no privileged shell" is a normal state for most devices
  /// and callers have to render it either way.
  static Future<ShellServiceResult> exec(
    String command, {
    RootAccess? grantedRoot,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final pick = await best(grantedRoot: grantedRoot);
    switch (pick.channel) {
      case PrivilegeChannel.root:
        final r = await RootAccess.exec(pick.root, command, timeout: timeout);
        return ShellServiceResult(
          ok: r.ok,
          exitCode: r.exitCode,
          stdout: r.stdout,
          stderr: r.stderr,
        );
      case PrivilegeChannel.adb:
        return AdbPairing.exec(command, timeout: timeout);
      case PrivilegeChannel.shizuku:
        return ShellService.exec(command, timeout: timeout);
      case PrivilegeChannel.none:
        return const ShellServiceResult(
          ok: false,
          exitCode: -1,
          stdout: '',
          stderr: 'No privileged shell. Grant root, or pair this device in '
              'Agent environment.',
        );
    }
  }

  /// Whether a rooted device should be offered ADB pairing at all.
  ///
  /// It should not. Pairing would be a setup flow that ends with strictly
  /// fewer capabilities than the user already has.
  static bool needsAdbPairing(PrivilegeChannel channel, RootAccess root) =>
      !root.isUsable && channel != PrivilegeChannel.adb;
}
