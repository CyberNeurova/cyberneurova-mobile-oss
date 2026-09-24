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
    // Confine even under PRoot. PRoot confines the shell PROCESS, but the
    // native-Dart file tools that share this session follow host symlinks, so a
    // `cd` through a symlink pointing outside the sandbox would let a later
    // file_read / file_write escape it (issue #2). The check runs in BOTH
    // modes; only what we record as cwd differs.
    if (_guestNamespace) {
      // Under PRoot both the existence check AND the confinement resolve
      // symlinks in the GUEST namespace: an absolute distro symlink like
      // `/var/run` -> `/run` means `<rootfs>/run`, not the HOST's `/run` (see
      // [resolveWithin]). Testing `Directory(_toHostPath(...)).existsSync()`
      // would follow the link natively to the host's `/run` — which need not
      // exist even though `<rootfs>/run` does — while a host canonicalisation
      // would walk a crafted link out of the sandbox.
      final host = _resolveWithinGuest(resolvedTarget);
      if (host == null) {
        return 'Refused: $target is outside the session directory';
      }
      if (!Directory(host).existsSync()) return 'No such directory: $target';
    } else {
      final dir = Directory(_toHostPath(resolvedTarget));
      if (!dir.existsSync()) return 'No such directory: $target';
      String canonical;
      try {
        canonical = dir.resolveSymbolicLinksSync();
      } catch (_) {
        canonical = dir.path;
      }
      if (!_withinHostRoots(canonical)) {
        return 'Refused: $target is outside the session directory';
      }
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
    return _guestNamespace
        ? _resolveWithinGuest(resolved)
        : _resolveWithinHost(resolved);
  }

  /// [resolveWithin] for the bare Android shell, where the shell's namespace IS
  /// the host's and [toHostPath] is identity: canonicalise on the host and
  /// confine to the real host roots.
  String? _resolveWithinHost(String resolved) {
    // The path Dart actually opens. Identity for Android's shell.
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
    // Confine on the HOST. The file tools run natively and follow host
    // symlinks, so a symlink whose canonical target escapes the container is a
    // sandbox escape (issue #2).
    if (!_withinHostRoots(canonicalProbe)) return null;

    // Re-attach whatever tail didn't exist yet (the host path the tools open).
    final tail = p.relative(hostResolved, from: probe);
    return tail == '.' ? canonicalProbe : p.join(canonicalProbe, tail);
  }

  /// [resolveWithin] for a PRoot guest, where the shell speaks guest paths and
  /// the native-Dart file tools would otherwise follow HOST symlinks.
  ///
  /// The difference that matters: an absolute GUEST symlink target is re-rooted
  /// under the rootfs, not followed to the host. `/var/run` -> `/run` means
  /// `<rootfs>/run`; `/etc/mtab` -> `/proc/self/mounts` means
  /// `<rootfs>/proc/self/mounts`. Host `resolveSymbolicLinksSync` reads those
  /// absolute targets in the HOST root, so the link either lands outside the
  /// rootfs and is over-rejected (you cannot enter `/var/run`, and `parentOf`
  /// drops the "up" row) or, for a symlink crafted to point at app-private host
  /// data like `/data/data/<pkg>/...`, walks straight out of the sandbox
  /// (issue #2).
  ///
  /// [_canonicalizeGuest] resolves the link in the guest namespace instead and
  /// returns the confined host path the tools then open — so both the browser
  /// and the file tools open the guest-re-rooted path rather than following the
  /// host link.
  String? _resolveWithinGuest(String resolved) {
    final canonGuest = _canonicalizeGuest(resolved);
    if (canonGuest == null) return null;

    // The re-rooted host path. Any GUEST symlink has already been resolved, so
    // the only symlinks left are in the HOST-side prefix (the real on-disk
    // location of the rootfs / bind-mounted home — `/data/data` -> `/data/user/0`
    // on Android). Canonicalise the nearest existing ancestor (the leaf may not
    // exist yet, for file_write) so the containment prefixes line up, then
    // re-attach the tail. This cannot re-follow a guest link out of the sandbox.
    final host = _toHostPath(canonGuest);
    var probe = host;
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
    final tail = p.relative(host, from: probe);
    final canonHost = tail == '.' ? canonicalProbe : p.join(canonicalProbe, tail);
    return _withinHostRoots(canonHost) ? canonHost : null;
  }

  /// Canonicalises [guestPath] in the GUEST namespace, following each symlink
  /// component and re-rooting an ABSOLUTE target under the rootfs via
  /// [toHostPath]. Returns the canonical guest path, or null when it cannot be
  /// confined:
  ///
  ///  * a symlink loop, or
  ///  * a followed symlink whose re-rooted target does not exist INSIDE the
  ///    sandbox — either a dangling link (nothing to read) or one crafted to
  ///    point at a host-only path such as `/data/data/<pkg>/...`, which has no
  ///    counterpart under the rootfs (issue #2). Refusing loses nothing a real
  ///    file tool could have read and closes the escape.
  ///
  /// A trailing component of the ORIGINAL path may legitimately not exist yet
  /// (file_write creating a new file); only symlink TARGETS must resolve to
  /// something real, which is what separates "create `/root/new.txt`" (allowed)
  /// from "follow `/root/escape` -> app-private data" (refused).
  String? _canonicalizeGuest(String guestPath) {
    // Each queued component carries whether it MUST already exist: original
    // path components may be created, components injected by following a symlink
    // must resolve to something real.
    final pending = <MapEntry<String, bool>>[];
    void pushAll(String path, {required bool mustExist}) {
      for (final c in p.posix.split(path.replaceAll(r'\', '/'))) {
        if (c.isEmpty || c == '.' || c == '/') continue;
        pending.add(MapEntry(c, mustExist));
      }
    }

    pushAll(guestPath, mustExist: false);
    final out = <String>[];
    var hops = 0;
    var i = 0;
    while (i < pending.length) {
      final entry = pending[i++];
      final comp = entry.key;
      final mustExist = entry.value;
      if (comp == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      final guestSoFar = '/${[...out, comp].join('/')}';
      final hostSoFar = _toHostPath(guestSoFar);
      FileSystemEntityType type;
      try {
        type = FileSystemEntity.typeSync(hostSoFar, followLinks: false);
      } catch (_) {
        type = FileSystemEntityType.notFound;
      }

      if (type == FileSystemEntityType.notFound) {
        // A re-rooted symlink target that is absent is an escape/dangling link.
        if (mustExist) return null;
        // An original, not-yet-created leaf: keep it and whatever follows
        // verbatim — nothing left under it exists to resolve.
        out.add(comp);
        for (; i < pending.length; i++) {
          final c = pending[i].key;
          if (c == '..') {
            if (out.isNotEmpty) out.removeLast();
          } else {
            out.add(c);
          }
        }
        break;
      }

      if (type != FileSystemEntityType.link) {
        out.add(comp);
        continue;
      }

      if (++hops > 40) return null; // symlink loop
      String linkTarget;
      try {
        linkTarget = Link(hostSoFar).targetSync().replaceAll(r'\', '/');
      } catch (_) {
        return null;
      }
      final rest = pending.sublist(i);
      pending.clear();
      if (p.posix.isAbsolute(linkTarget)) {
        // GUEST-absolute: restart from the guest root so toHostPath re-roots it
        // under the rootfs (or the bind-mounted home for `/root/...`).
        out.clear();
        pushAll(linkTarget, mustExist: true);
      } else {
        // Relative to the link's own directory.
        final base = out.isEmpty ? '' : out.join('/');
        out.clear();
        pushAll(p.posix.normalize('/$base/$linkTarget'), mustExist: true);
      }
      pending.addAll(rest);
      i = 0;
    }
    return '/${out.join('/')}';
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

  /// True under PRoot, where the shell's namespace (`/`, `/root`) differs from
  /// the host's and [toHostPath] is a real translation. On the bare Android
  /// shell the two coincide and [rootDir] is the host container path, never `/`
  /// — so this is the one honest signal for "resolve symlinks in the guest
  /// namespace" without threading a backend flag through the session.
  bool get _guestNamespace => rootDir == '/';

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
