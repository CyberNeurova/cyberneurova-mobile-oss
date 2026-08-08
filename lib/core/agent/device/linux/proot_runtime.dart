import 'dart:io';

import 'package:path/path.dart' as p;

/// Invokes PRoot correctly on Android.
///
/// PRoot gives us a real Linux userland without root: it intercepts syscalls
/// with `ptrace` and rewrites paths, so a Debian/Ubuntu/Kali rootfs unpacked
/// into app storage behaves like `/`. That is what makes `apt` work.
///
/// **This only functions on the `direct` flavour.** PRoot must `execve` the
/// guest's binaries, and `targetSdk 28` is what permits executing files we
/// wrote — measured on the A54, see `docs/shell/14-FLAVOURS.md`. On `play`
/// the same call returns `Permission denied`, so [isSupported] gates it and
/// `DeviceCapabilities` withholds the capability rather than letting the agent
/// discover it by failing.
///
/// ## Why the environment matters more than the arguments
///
/// A stock PRoot build assumes a normal Linux host. Android is not one, and
/// each assumption has to be corrected explicitly:
///
/// * **`PROOT_TMP_DIR`** — PRoot extracts its embedded loader to a temp
///   directory and defaults to `/tmp`, which does not exist on Android. Unset,
///   PRoot fails at startup with an error that reads like a corrupt binary.
/// * **`PROOT_LOADER`** — when a build ships its loader as a separate file
///   rather than embedding it, PRoot must be told where it is; the compiled-in
///   path points at the packager's prefix, not ours.
/// * **`LD_LIBRARY_PATH`** — the upstream binary links against `libtalloc`,
///   which we vendor next to it. Without this it resolves nothing.
///
/// All three are why a binary that "works in Termux" does nothing in our app:
/// nothing is wrong with the binary, it is simply looking in Termux's prefix.
class ProotRuntime {
  const ProotRuntime({
    required this.prootPath,
    required this.tmpDir,
    this.loaderPath,
    this.libDir,
  });

  /// The `proot` executable — a symlink in `$PREFIX/bin` pointing into
  /// `nativeLibraryDir`, the only place we may execute from.
  final String prootPath;

  /// Writable scratch for the extracted loader. Ours, not `/tmp`.
  final String tmpDir;

  /// Explicit loader path, for builds that don't embed it.
  final String? loaderPath;

  /// Where `libtalloc` and friends live, if the build is dynamically linked.
  final String? libDir;

  static bool get isSupported => Platform.isAndroid;

  /// Builds the argv for running [command] inside [rootfs].
  ///
  /// The bind mounts are not optional decoration — each one is something a
  /// real distro expects to exist and will misbehave without:
  ///
  /// * `/proc`, `/sys`, `/dev` — package scripts, `ps`, and anything reading
  ///   process state. Without `/proc`, `apt` itself fails.
  /// * `/dev/urandom` — apt's signature verification needs entropy.
  /// * `/sdcard` — the one bridge to the user's own files, so a tool can
  ///   actually operate on something they care about.
  ///
  /// `-0` makes the guest *believe* it is uid 0, which is what lets `apt`
  /// write to `/usr` inside the rootfs. It grants **no kernel capability** —
  /// see [rootIsFake].
  List<String> argsFor({
    required String rootfs,
    required List<String> command,
    String workingDir = '/root',
    Map<String, String> extraBinds = const {},
  }) {
    return [
      // Fake root: required for apt to write into the rootfs. Not real root.
      '-0',
      // Follow symlinks that escape the rootfs rather than dangling.
      '-L',
      '--kill-on-exit',
      '--rootfs=$rootfs',
      '--cwd=$workingDir',
      '--bind=/proc',
      '--bind=/sys',
      '--bind=/dev',
      '--bind=/dev/urandom:/dev/random',
      // Android has no /proc/self/fd -> /dev/fd link some scripts expect.
      '--bind=/proc/self/fd:/dev/fd',
      '--bind=/proc/self/fd/0:/dev/stdin',
      '--bind=/proc/self/fd/1:/dev/stdout',
      '--bind=/proc/self/fd/2:/dev/stderr',
      for (final e in extraBinds.entries) '--bind=${e.key}:${e.value}',
      ...command,
    ];
  }

  /// Environment for the PRoot process itself (not the guest's).
  Map<String, String> get processEnv => {
        'PROOT_TMP_DIR': tmpDir,
        if (loaderPath != null) 'PROOT_LOADER': loaderPath!,
        if (libDir != null) 'LD_LIBRARY_PATH': libDir!,
      };

  /// Environment handed to the guest — a plausible Linux, not Android's.
  ///
  /// `PATH` is the distro's, deliberately excluding Android's `/system/bin`:
  /// leaking toybox into a Debian guest gives you two `ls` implementations
  /// with different flags, and scripts break in ways that are miserable to
  /// debug.
  Map<String, String> guestEnv({String home = '/root', String? term}) => {
        'HOME': home,
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        'TERM': term ?? 'xterm-256color',
        'LANG': 'C.UTF-8',
        // Debian's postinst scripts prompt without this and hang a shell that
        // has no one watching it.
        'DEBIAN_FRONTEND': 'noninteractive',
        'PROOT_NO_SECCOMP': '1',
      };

  /// Whether the vendored binary is actually present and linked.
  bool get isInstalled =>
      File(prootPath).existsSync() || Link(prootPath).existsSync();

  /// **PRoot's `-0` is a lie the guest believes, not a privilege we gained.**
  ///
  /// Stated as API rather than a comment because the agent has to be told, and
  /// because it is the single most common wrong assumption about PRoot. Inside
  /// the guest `id` prints `uid=0(root)` and `apt install` works — but no
  /// kernel capability was granted. Anything needing a real capability still
  /// fails:
  ///
  /// * `nmap -sS` (SYN scan) — needs `CAP_NET_RAW`. Use `-sT`.
  /// * `ping` — same, unless the distro's binary falls back to a datagram
  ///   socket.
  /// * `tcpdump` — cannot open a capture device.
  /// * mounting, `iptables`, changing the real uid — all refused.
  ///
  /// The agent must have this in its prompt or it will propose a SYN scan,
  /// watch it fail, and propose it again.
  static const bool rootIsFake = true;

  /// Roughly what syscall interception costs. From `01-ANDROID-RUNTIME.md`
  /// §4.2 — fine for tooling, bad for compiling.
  static const String performanceNote = '2-5x slower on syscall-heavy work';

  /// Where the vendored binary is expected to sit, given a prefix.
  static String expectedBinary(String prefixDir) =>
      p.join(prefixDir, 'bin', 'proot');
}
