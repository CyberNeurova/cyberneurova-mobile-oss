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
    bool enforceContainment = true,
  })  : _cwd = cwd ?? homeDir ?? rootDir,
        homeDir = homeDir ?? cwd ?? rootDir,
        _env = {...?env},
        _toHostPath = toHostPath ?? _identity,
        _enforceContainment = enforceContainment;

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

  /// Whether to apply the host-side sandbox check.
  ///
  /// Off under PRoot: the rootfs **is** the boundary and PRoot enforces it on
  /// every syscall. Re-checking here would add a second, subtly different
  /// notion of "outside" that rejects legitimate guest paths.
  final bool _enforceContainment;

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

    // Under PRoot the shell's namespace is the guest's, so the *guest* path is
    // what must be recorded — resolving symlinks on the host would hand back a
    // path the shell has never heard of.
    if (!_enforceContainment) {
      _cwd = resolvedTarget;
      return null;
    }

    String canonical;
    try {
      canonical = dir.resolveSymbolicLinksSync();
    } catch (_) {
      canonical = resolvedTarget;
    }
    if (!_within(canonical)) {
      return 'Refused: $target is outside the session directory';
    }
    _cwd = canonical;
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

    // PRoot confines the guest itself, so a guest path needs no host-side
    // containment — only translation, so callers get something Dart can open.
    if (!_enforceContainment) return _toHostPath(resolved);

    // Walk up to the nearest existing ancestor so a not-yet-created file is
    // still checked against a real, symlink-resolved path.
    var probe = resolved;
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
    if (!_within(canonicalProbe)) return null;

    // Re-attach whatever tail didn't exist yet.
    final tail = p.relative(resolved, from: probe);
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

  bool _within(String candidate) {
    String root;
    try {
      root = Directory(rootDir).resolveSymbolicLinksSync();
    } catch (_) {
      root = rootDir;
    }
    return p.equals(candidate, root) || p.isWithin(root, candidate);
  }
}
