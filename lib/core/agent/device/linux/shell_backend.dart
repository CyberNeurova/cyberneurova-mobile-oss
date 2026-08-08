import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/proot_runtime.dart';

/// What a shell actually runs on.
///
/// Two of these exist and the difference is total: Android's own mksh, versus
/// a real Linux distribution under PRoot. Everything above this — the PTY, the
/// panes, `shell_exec`, the scrollback, the agent — is written against the
/// abstraction, so swapping backends does not touch any of it.
///
/// The awkward part, and the reason this is an interface rather than a couple
/// of if-statements: **paths mean different things on each side.** Inside a
/// PRoot guest, `/root` is a guest path that does not exist on the host; the
/// host path is `<rootfs>/root`. The shell, the user and the agent all speak
/// guest paths, while Dart's `File` and `Directory` speak host paths. Every
/// crossing goes through [toHostPath], and forgetting one produces a file tool
/// that reports "no such file" for a file the terminal can `cat`.
abstract class ShellBackend {
  /// Human label for the UI — "Android" or "Alpine Linux 3.21.7".
  String get label;

  /// Short id for telemetry and the agent's prompt.
  String get id;

  /// The program to spawn.
  String get executable;

  /// Arguments that start an **interactive login shell** (the PTY path).
  /// [workingDir] is where the shell should START, as a path in whatever
  /// namespace this backend speaks. Defaults to [initialCwd]; the session
  /// passes its own directory so the terminal and the model's view of "here"
  /// cannot drift apart.
  List<String> interactiveArgs({String? workingDir});

  /// Arguments that run [command] once and exit (the `shell_exec` path).
  List<String> commandArgs(String command, {String? workingDir});

  /// Environment for the spawned process.
  Map<String, String> environment({String? term});

  /// The directory a fresh session starts in, in whatever namespace the shell
  /// uses.
  String get initialCwd;

  /// The boundary the session may not escape, in the same namespace.
  String get rootDir;

  /// Translates a path the *shell* understands into one Dart can open.
  ///
  /// Identity on Android. On PRoot it prefixes the rootfs.
  String toHostPath(String shellPath);

  /// Whether the host-side sandbox check applies.
  ///
  /// False under PRoot: the rootfs **is** the boundary and PRoot enforces it
  /// on every syscall, so re-checking with host-path arithmetic would only add
  /// a second, subtly different notion of "outside" that rejects legitimate
  /// guest paths.
  bool get enforceHostContainment;

  /// True when the shell reports a *fake* uid 0 — see [ProotRuntime.rootIsFake].
  bool get hasFakeRoot;
}

/// Android's own shell. Always available, no install, ~210 toybox applets.
class AndroidShellBackend implements ShellBackend {
  const AndroidShellBackend({required this.homeDir, required this.prefixDir});

  final String homeDir;
  final String prefixDir;

  @override
  String get label => 'Android shell';

  @override
  String get id => 'android';

  @override
  String get executable => '/system/bin/sh';

  @override
  // Android's shell takes its cwd from the process spawn, not from an
  // argument, so there is nothing to place here.
  List<String> interactiveArgs({String? workingDir}) => const [];

  @override
  List<String> commandArgs(String command, {String? workingDir}) =>
      ['-c', command];

  @override
  Map<String, String> environment({String? term}) => {
        'TERM': term ?? 'xterm-256color',
        'HOME': homeDir,
        'TMPDIR': p.join(prefixDir, 'tmp'),
        'PREFIX': prefixDir,
      };

  @override
  String get initialCwd => homeDir;

  @override
  String get rootDir => homeDir;

  @override
  String toHostPath(String shellPath) => shellPath;

  @override
  bool get enforceHostContainment => true;

  @override
  bool get hasFakeRoot => false;
}

/// A real Linux distribution, under PRoot.
///
/// The shell is the guest's own `/bin/sh` — busybox ash on Alpine, bash on
/// Debian — so everything a distro expects is present: its own coreutils, its
/// package manager, its `/etc`, its libraries.
class ProotShellBackend implements ShellBackend {
  const ProotShellBackend({
    required this.distro,
    required this.rootfsPath,
    required this.runtime,
    required this.homeDir,
  });

  final Distro distro;
  final String rootfsPath;
  final ProotRuntime runtime;

  /// Host directory bind-mounted over the guest's `/root`.
  ///
  /// The user's files must not live inside the rootfs. Removing or switching
  /// a distro deletes `distros/<id>` recursively, and `/root` — where every
  /// shell starts and where agents write — sits right inside it. Anything the
  /// user or an agent built would go with it.
  ///
  /// Binding a directory from outside the rootfs over `/root` means the files
  /// outlive the distribution they were made in. It also means the Android
  /// shell and the PRoot shell see the same home, so switching backends (or
  /// flavours) does not hide someone's work either.
  final String homeDir;

  /// `/root` is the guest's home, and the host directory that backs it.
  Map<String, String> get _binds => {homeDir: '/root'};

  @override
  String get label => '${distro.name} ${distro.version}';

  @override
  String get id => distro.id;

  @override
  String get executable => runtime.prootPath;

  /// The best interactive shell this rootfs actually has.
  ///
  /// `/bin/sh` is dash on Debian and Kali and busybox ash on Alpine, and
  /// **none of them do tab completion**. So pressing tab in the terminal did
  /// nothing at all — reported as "tab just skips", which is exactly right:
  /// the key was arriving, there was simply nothing on the other end to
  /// complete with. bash is what people mean by "a shell that completes", and
  /// Kali ships it; Alpine does not unless asked, hence the fallback.
  ///
  /// Checked on the HOST side, where the rootfs is an ordinary directory —
  /// there is no guest to ask before the guest is running.
  String get _interactiveShell {
    for (final candidate in const ['/bin/bash', '/usr/bin/bash']) {
      if (File(p.join(rootfsPath, candidate.substring(1))).existsSync()) {
        return candidate;
      }
    }
    return '/bin/sh';
  }

  /// A login shell, so the guest's own profile runs and `$PATH` ends up as the
  /// distribution intends rather than as we guessed.
  @override
  List<String> interactiveArgs({String? workingDir}) => runtime.argsFor(
        rootfs: rootfsPath,
        workingDir: workingDir ?? initialCwd,
        command: [_interactiveShell, '-l'],
        extraBinds: _binds,
      );

  @override
  List<String> commandArgs(String command, {String? workingDir}) =>
      runtime.argsFor(
        rootfs: rootfsPath,
        workingDir: workingDir ?? initialCwd,
        command: ['/bin/sh', '-c', command],
        extraBinds: _binds,
      );

  /// Both halves matter: PRoot's own variables (loader, temp dir, library
  /// path) and the guest's (`PATH`, `HOME`, `TERM`). They are separate
  /// namespaces that happen to travel in one environment block.
  @override
  Map<String, String> environment({String? term}) => {
        ...runtime.processEnv,
        ...runtime.guestEnv(home: initialCwd, term: term),
      };

  /// `/root`, because PRoot runs the guest as (fake) root and that is where a
  /// distro expects root's home to be.
  @override
  String get initialCwd => '/root';

  @override
  String get rootDir => '/';

  /// Both sides of this translation are POSIX — the guest is Linux and the
  /// host is Android — so join with the posix context explicitly rather than
  /// whatever the running platform happens to use. `p.join` follows the host
  /// separator, which silently produces backslashes when these run anywhere
  /// but a device.
  @override
  String toHostPath(String shellPath) {
    if (!p.posix.isAbsolute(shellPath)) return p.posix.join(homeDir, shellPath);
    // `/root` is bind-mounted, so it does NOT live under the rootfs —
    // resolving it there would point file tools at an empty directory inside
    // the distribution while the real file sits in the persistent home.
    if (shellPath == '/root') return homeDir;
    if (shellPath.startsWith('/root/')) {
      return p.posix.join(homeDir, shellPath.substring('/root/'.length));
    }
    // `/etc/hosts` (guest) -> `<rootfs>/etc/hosts` (host).
    return p.posix.join(rootfsPath, shellPath.substring(1));
  }

  @override
  bool get enforceHostContainment => false;

  @override
  bool get hasFakeRoot => true;
}
