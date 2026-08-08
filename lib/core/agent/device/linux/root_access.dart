import 'dart:io';

/// Whether this device can give us a real root shell, and how.
///
/// **Detection only.** This never attempts to obtain root, never suggests
/// rooting, and never hints at how. If `su` is absent the answer is simply no
/// and the PRoot path is used. Rooting someone's phone is their decision, made
/// elsewhere, and an app that nudges toward it is doing something else.
enum RootStatus {
  /// No `su` found, or it exists and did not yield uid 0.
  unavailable,

  /// `su` is present but has not been exercised yet — a manager like Magisk
  /// will prompt on first use, and the user may refuse.
  present,

  /// Verified: `su -c id` returned uid=0.
  granted,

  /// `su` exists and the request was actively denied. Distinct from
  /// [unavailable] because retrying may succeed if the user changes their
  /// mind, whereas an absent binary will never appear.
  denied,
}

/// Result of probing for root.
class RootAccess {
  const RootAccess({required this.status, this.suPath, this.detail});

  final RootStatus status;

  /// The `su` binary that answered, when one did.
  final String? suPath;

  /// Human-readable note for the settings screen — why we concluded what we
  /// concluded. Never shown as an error; not having root is normal.
  final String? detail;

  bool get isUsable => status == RootStatus.granted;

  static const _candidates = [
    '/system/bin/su',
    '/system/xbin/su',
    '/sbin/su',
    '/su/bin/su',
    '/system/sbin/su',
    '/vendor/bin/su',
    '/debug_ramdisk/su',
  ];

  /// Looks for a `su` binary without running anything.
  ///
  /// Split from [verify] on purpose: finding the file is silent, but *running*
  /// it makes Magisk raise a permission dialog. Showing that dialog
  /// unprompted, at app start, before the user has asked for anything, would
  /// be startling and would train people to tap Deny.
  static Future<RootAccess> detect() async {
    if (!Platform.isAndroid) {
      return const RootAccess(
        status: RootStatus.unavailable,
        detail: 'Root shells are an Android concept.',
      );
    }

    for (final path in _candidates) {
      if (File(path).existsSync()) {
        return RootAccess(
          status: RootStatus.present,
          suPath: path,
          detail: 'Found su at $path. Not exercised yet.',
        );
      }
    }

    // PATH lookup last: the fixed list covers every manager we know of, and
    // `which` costs a process spawn.
    try {
      final r = await Process.run('/system/bin/which', ['su']);
      final out = '${r.stdout}'.trim();
      if (r.exitCode == 0 && out.isNotEmpty) {
        return RootAccess(
          status: RootStatus.present,
          suPath: out.split('\n').first.trim(),
          detail: 'Found su on PATH. Not exercised yet.',
        );
      }
    } on ProcessException {
      // No `which`; the fixed list was the real check anyway.
    }

    return const RootAccess(
      status: RootStatus.unavailable,
      detail: 'No su binary. The Console uses PRoot, which needs no root.',
    );
  }

  /// Runs [command] as root.
  ///
  /// The whole reason a rooted device needs no ADB pairing: `su -c` already
  /// gives everything the shell uid gives, plus the kernel capabilities it
  /// does not — raw sockets, packet capture, monitor mode. Asking such a user
  /// to pair over wireless debugging would be strictly worse for no gain.
  ///
  /// Never throws; a failure is an ordinary result here, not an exception.
  static Future<({bool ok, int exitCode, String stdout, String stderr})> exec(
    RootAccess access,
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final su = access.suPath;
    if (su == null || !access.isUsable) {
      return (ok: false, exitCode: -1, stdout: '', stderr: 'Root not granted.');
    }
    try {
      final r = await Process.run(su, ['-c', command]).timeout(timeout);
      return (
        ok: r.exitCode == 0,
        exitCode: r.exitCode,
        stdout: '${r.stdout}',
        stderr: '${r.stderr}',
      );
    } on ProcessException catch (e) {
      return (ok: false, exitCode: -1, stdout: '', stderr: e.message);
    } catch (e) {
      return (ok: false, exitCode: -1, stdout: '', stderr: '$e');
    }
  }

  /// Actually asks for root, which may show the user a prompt.
  ///
  /// Call this only when the user has asked for the privileged path — never
  /// speculatively. Verifies by asking `id` for the uid rather than trusting
  /// an exit code, because some managers return 0 for a denied request.
  static Future<RootAccess> verify(RootAccess found) async {
    final su = found.suPath;
    if (su == null) return found;

    try {
      final r = await Process.run(su, ['-c', 'id -u']).timeout(
        // A prompt the user never answers must not hang the caller forever.
        const Duration(seconds: 30),
      );
      final uid = '${r.stdout}'.trim();
      if (uid == '0') {
        return RootAccess(
          status: RootStatus.granted,
          suPath: su,
          detail: 'Verified: su returned uid 0.',
        );
      }
      return RootAccess(
        status: RootStatus.denied,
        suPath: su,
        detail: uid.isEmpty
            ? 'The root request was refused.'
            : 'su ran but reported uid $uid, not 0.',
      );
    } on ProcessException catch (e) {
      return RootAccess(
        status: RootStatus.denied,
        suPath: su,
        detail: 'Could not run su: ${e.message}',
      );
    } catch (e) {
      return RootAccess(
        status: RootStatus.denied,
        suPath: su,
        detail: 'Root request did not complete: $e',
      );
    }
  }
}
