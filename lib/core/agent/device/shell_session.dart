import 'dart:io';

import 'package:path/path.dart' as p;

/// One shell context per session: working directory and environment.
///
/// This exists to hold the invariant `docs/shell/00-OVERVIEW.md` §1 calls the
/// single most important design constraint of the feature:
///
/// > the terminal and the agent share one session, one working directory,
/// > one environment, one scrollback.
///
/// So when the agent runs `cd /sdcard/scans`, the user's next typed command
/// starts there — and vice versa. Both input paths read and mutate *this*
/// object rather than each keeping their own cwd, which is what makes the
/// feature feel like pair-programming instead of two disconnected tools.
///
/// Deliberately not a Riverpod provider: the terminal path (a PTY, when it
/// lands) needs the same instance, and keeping it a plain object means
/// `nsh_session`-style pure-Dart tests can drive it without a widget tree.
class ShellSession {
  ShellSession({
    required this.rootDir,
    String? cwd,
    String? homeDir,
    Map<String, String>? env,
    String Function(String)? toHostPath,
    // Retained for the construction API (callers still pass it) but INERT: the
    // host-side containment check now runs UNCONDITIONALLY in both backends,
    // because the native-Dart file tools follow host symlinks even under PRoot
    // (OSS issue #2). It no longer gates anything.
    // ignore: avoid_unused_constructor_parameters
    bool enforceContainment = true,
  })  : _cwd = cwd ?? homeDir ?? rootDir,
        homeDir = homeDir ?? cwd ?? rootDir,
        _env = {...?env},
        _toHostPath = toHostPath ?? _identity;

  /// Where `~` and a bare `cd` land.
  ///
  /// Distinct from [rootDir]: under PRoot the sandbox root is the guest's
  /// `/` but home is `/root`, so resolving `~` to the root sent people to the
  /// top of the filesystem instead of to their files. On Android's shell the
  /// two coincide.
  final String homeDir;

  static String _identity(String s) => s;

  /// Turns a path *the shell* understands into one Dart can open.
  ///
  /// Identity for Android's shell. Under PRoot the two namespaces differ:
  /// the shell's `/etc/hosts` is the host's `<rootfs>/etc/hosts`, and every
  /// `File`/`Directory` call here has to cross that boundary or it will report
  /// "no such file" for a file the terminal can `cat`.
  final String Function(String) _toHostPath;

  /// Exposed so tools that touch the filesystem translate the same way the
  /// session does, rather than each inventing its own mapping.
  String hostPathOf(String shellPath) => _toHostPath(shellPath);

  /// The session sandbox root. Nothing may `cd` above this — on Android the
  /// app can only read its own container plus whatever the user granted, and
  /// letting the agent wander to `/` produces confusing permission errors
  /// rather than useful output.
  final String rootDir;

  String _cwd;
  final Map<String, String> _env;

  String get cwd => _cwd;
  Map<String, String> get env => Map.unmodifiable(_env);

  void setEnv(String key, String value) => _env[key] = value;

  /// Moves the session's working directory.
  ///
  /// Returns null on success, or a human message on failure. Rejects anything
  /// that escapes [rootDir] — including via `..` and symlink games, which is
  /// why the resolved path is compared rather than the literal one.
  String? changeDirectory(String target) {
    final resolvedTarget = _resolve(target);
    final dir = Directory(_toHostPath(resolvedTarget));
    if (!dir.existsSync()) return 'No such directory: $target';

    // Canonicalize on the HOST and refuse anything that escapes the real host
    // roots — even under PRoot. PRoot confines the shell PROCESS, but the
    // native-Dart file tools that share this session follow host symlinks, so a
    // `cd` through a host symlink pointing outside the sandbox would let a
    // later file_read / file_write escape it (issue #2). The host check runs in
    // BOTH modes; only what we record as cwd differs.
    String canonical;
    try {
      canonical = dir.resolveSymbolicLinksSync();
    } catch (_) {
      canonical = dir.path;
    }
    if (!_withinHostRoots(canonical)) {
      return 'Refused: $target is outside the session directory';
    }

    // Record the path in the shell's OWN namespace — the guest path under PRoot,
    // the container path on the bare Android shell — because that is what `pwd`,
    // the breadcrumb and `parentOf`/`display` all speak. Storing the
    // host-canonical form (used only for the containment check above) drifted
    // the cwd into a different namespace: on Android `/data/data/<pkg>` is a
    // symlink to `/data/user/0/<pkg>`, so after a `cd` the breadcrumb stopped
    // collapsing to `~` and the "up" row was computed against the wrong root —
    // navigation back out appeared to fail. The security check already ran on
    // `canonical`; what we store here is only ever a label.
    _cwd = resolvedTarget;
    return null;
  }

  /// Resolves [target] against the session cwd and returns it only if it
  /// stays inside [rootDir]; returns null otherwise.
  ///
  /// This is the single containment check the file tools share with `cd`, so
  /// there is one sandbox boundary rather than one per tool. Works for paths
  /// that don't exist yet (file_write): when the leaf is absent the check
  /// falls back to the nearest existing ancestor, which is what actually
  /// matters — you cannot create a file inside a directory you can't reach.
  String? resolveWithin(String target) {
    final resolved = _resolve(target);
    // The path Dart actually opens. Identity for Android's shell; under PRoot
    // it crosses the guest→host boundary.
    final hostResolved = _toHostPath(resolved);

    // Walk up to the nearest existing HOST ancestor so a not-yet-created file
    // is still checked against a real, symlink-resolved host path.
    var probe = hostResolved;
    while (probe.isNotEmpty &&
        !Directory(probe).existsSync() &&
        !File(probe).existsSync()) {
      final parent = p.dirname(probe);
      if (parent == probe) break;
      probe = parent;
    }

    String canonicalProbe;
    try {
      canonicalProbe = Directory(probe).existsSync()
          ? Directory(probe).resolveSymbolicLinksSync()
          : File(probe).resolveSymbolicLinksSync();
    } catch (_) {
      canonicalProbe = probe;
    }
    // Confine on the HOST even under PRoot. The file tools run natively and
    // follow host symlinks, so a symlink whose canonical target escapes BOTH
    // the rootfs and the bind-mounted home is a sandbox escape — PRoot confines
    // the shell process, not these Dart File calls (issue #2). The old
    // `!_enforceContainment` short-circuit returned the un-canonicalized host
    // path here, which is exactly what let file_read / file_write follow a
    // guest-planted symlink out to app-private data.
    if (!_withinHostRoots(canonicalProbe)) return null;

    // Re-attach whatever tail didn't exist yet (the host path the tools open).
    final tail = p.relative(hostResolved, from: probe);
    return tail == '.' ? canonicalProbe : p.join(canonicalProbe, tail);
  }

  /// Absolutises [target] in the SHELL's namespace — what `pwd` would print.
  ///
  /// Distinct from [resolveWithin], which answers the other question: the path
  /// Dart can open. Under PRoot those differ, and a UI showing the host answer
  /// tells the user their working directory is
  /// `/data/data/ai.cyberneurova.app/...` when the terminal right next to it
  /// says `/root`.
  String absolutePath(String target) => _resolve(target);

  /// Absolutises a path against the current cwd without touching the disk.
  ///
  /// Uses `package:path` rather than hand-rolled `/` splitting so the same
  /// code is correct on POSIX (where it actually runs) and on the host during
  /// `flutter test` — `docs/shell/07-REPO-STRUCTURE.md` calls out that session
  /// state must stay unit-testable without a device.
  String _resolve(String target) {
    if (target.isEmpty || target == '~') return homeDir;
    // `~/scans` is home-relative, not cwd-relative.
    if (target.startsWith('~/')) {
      return p.normalize(p.join(homeDir, target.substring(2)));
    }
    return p.normalize(
      p.isAbsolute(target) ? target : p.join(_cwd, target),
    );
  }

  /// The real HOST directories the native-Dart file tools may touch, each
  /// symlink-resolved: the sandbox rootfs, plus — under PRoot — the
  /// bind-mounted guest home (`/root` maps to a host dir OUTSIDE the rootfs). A
  /// path whose canonical form escapes ALL of these is a sandbox escape.
  List<String> _hostRootsCanonical() {
    final roots = <String>[];
    void add(String hostPath) {
      String canon;
      try {
        canon = Directory(hostPath).resolveSymbolicLinksSync();
      } catch (_) {
        canon = hostPath;
      }
      if (!roots.any((r) => p.equals(r, canon))) roots.add(canon);
    }

    // The rootfs on the HOST. Under PRoot `rootDir` is the GUEST `/`
    // (shell_workspace passes guest paths), so it must be TRANSLATED to the
    // host — using rootDir raw would resolve to the device's real `/` and
    // confine nothing. On Android's shell `toHostPath` is identity and rootDir
    // is already the host container, so this is a no-op there.
    add(_toHostPath(rootDir));
    // The home the file tools may reach — under PRoot a bind-mount that sits
    // OUTSIDE the rootfs, so it's a legitimate second root. On Android home ==
    // root and this dedups away.
    add(_toHostPath(homeDir));
    return roots;
  }

  bool _withinHostRoots(String candidate) {
    for (final root in _hostRootsCanonical()) {
      if (p.equals(candidate, root) || p.isWithin(root, candidate)) return true;
    }
    return false;
  }
}
