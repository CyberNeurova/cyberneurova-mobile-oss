import 'dart:io';

import 'package:path/path.dart' as p;

/// Makes bundled native tools runnable from a shell.
///
/// ## Why this exists
///
/// `docs/shell/01-ANDROID-RUNTIME.md` §1, **confirmed on our own hardware**
/// (`SPIKE-RESULTS.md`): an app with a modern `targetSdk` cannot execute a
/// binary it writes into its own data directory. We measured it on Android 16
/// — a file we own, `chmod 755`, still `Permission denied`, because the denial
/// is SELinux on `app_data_file`, not the permission bits.
///
/// There is exactly **one** directory an app can execute from at any
/// `targetSdk`: **`nativeLibraryDir`** (`/data/app/~~<hash>/<pkg>-<hash>/lib/
/// <abi>/`). The package installer populates it from the APK's `lib/<abi>/`
/// entries, it is read-only, and it carries a label that permits execution.
///
/// So a bundled tool ships as `lib<name>.so` in `android/app/src/main/jniLibs/
/// <abi>/`, lands in `nativeLibraryDir` at install time, and is executable
/// there. The catch is the *name*: a shell needs `nmap`, not `libnmap.so`.
///
/// ## What it does
///
/// Builds a `$PREFIX/bin` of **symlinks** pointing back into
/// `nativeLibraryDir`, so `$PATH` lookups resolve to real names while the
/// executable bytes stay in the only place they are allowed to be. Symlinking
/// is deliberate — *copying* them into `$PREFIX/bin` would land them on
/// `app_data_file` and they would stop being executable, which is the exact
/// trap this class exists to avoid.
///
/// Busybox and toybox are multicall binaries: they dispatch on `argv[0]`, so
/// one file becomes hundreds of commands purely through symlink names. That
/// is the highest-leverage part of the bootstrap — `01-ANDROID-RUNTIME.md`
/// §3 says the same.
class PrefixBootstrap {
  PrefixBootstrap({
    required this.prefixDir,
    required this.nativeLibraryDir,
  });

  /// Session root; `bin/` is created underneath it.
  final String prefixDir;

  /// The app's `nativeLibraryDir`, from the platform side. The one executable
  /// directory available to us.
  final String nativeLibraryDir;

  String get binDir => p.join(prefixDir, 'bin');

  /// Tools we ship, mapped to the applet names they should expose.
  ///
  /// Keyed by the `lib*.so` basename as it appears in `nativeLibraryDir`.
  /// A multicall binary lists the applets it answers to; a single-purpose
  /// binary lists just its own name.
  ///
  /// Empty by default: the toolchain is added per flavour, and claiming a
  /// tool we did not ship would make the agent propose a technique that then
  /// fails — the failure mode `DeviceCapabilities` exists to prevent.
  static const Map<String, List<String>> defaultToolset = {
    // Proof binary: a two-applet multicall built with the NDK, shipped to
    // demonstrate that the whole path works on a PLAY targetSdk. Real tools
    // (busybox ~350 applets, nmap, tcpdump) slot in exactly here.
    'libcntool.so': ['cn-hello', 'cn-arch'],
    // PRoot — vendored from termux/proot, see tools/pkg_core/VENDORED.md.
    // Only useful on the `direct` flavour, where executing a downloaded rootfs
    // is permitted; harmless on `play`, where it links but has nothing to run.
    'libproot.so': ['proot'],
    // PRoot's loader. NOT optional and easy to miss: Termux ships it at
    // `libexec/proot/loader`, so an extraction that only looks in bin/ and
    // lib/ silently drops it — and PRoot then fails every guest exec with
    // "No such file or directory" plus a hint list whose LAST entry is the
    // real cause. It performs the actual exec of the guest binary, so without
    // it PRoot starts fine and can run nothing.
    'libprootloader.so': ['proot-loader'],
    // BusyBox, built by us from upstream source against Bionic with the NDK
    // (tools/pkg_core/build_busybox.sh). Two vendored builds failed first and
    // both failures are worth remembering:
    //
    //  - Alpine's `busybox-static` is musl. Android's seccomp filter kills it
    //    with SIGSYS the instant the app spawns it (exit -31). It runs fine
    //    under `adb shell`, a different domain — so shell testing proves
    //    nothing about what the app may execute.
    //  - Termux's is Bionic but split into a launcher plus a core library
    //    that needs Termux's own libandroid-selinux.so, which we do not ship.
    //
    // Ours links against nothing but Android's libc, so there is no runtime
    // dependency to get wrong. Built from a minimal config — the decompressors
    // and tar, nothing else — because BusyBox's full config assumes glibc in a
    // dozen places Android lacks. That is also why it is 96 KB, not 1 MB.
    //
    // `xz` is absent on purpose: only the DEcompressors are built, so `unxz`
    // and `xzcat` exist and there is nothing to compress with. Listing an
    // applet the binary lacks would create a symlink that fails when run.
    //
    // `tar` is not symlinked either: a multicall dispatches on argv[0], so a
    // symlink named `tar` would shadow Android's own tar for anything on
    // $PATH. Callers invoke `busybox tar …` through the `busybox` symlink.
    'libbusybox.so': ['busybox', 'xzcat', 'unxz', 'gunzip', 'bunzip2'],
    // 'libnmapcore.so': ['nmap'],
  };

  /// Shared libraries that must be reachable under their **SONAME**, which is
  /// usually not a name Android will ship.
  ///
  /// The installer only extracts files matching `lib*.so`, so a library whose
  /// real name is `libtalloc.so.2` cannot be placed in `jniLibs` under that
  /// name — it would simply not be installed. We ship it as `libtalloc.so` and
  /// link the SONAME to it here.
  ///
  /// This matters because the dynamic linker looks for the **literal string in
  /// proot's `DT_NEEDED`**, which is `libtalloc.so.2`. Ship the file without
  /// this mapping and proot dies at startup with "library not found" for a
  /// library that is right there on disk.
  ///
  /// Keyed by shipped filename → the SONAMEs to expose in `$PREFIX/lib`.
  static const Map<String, List<String>> defaultLibraryAliases = {
    'libtalloc.so': ['libtalloc.so.2'],
  };

  /// `$PREFIX/lib` — SONAME symlinks, for `LD_LIBRARY_PATH`.
  String get libDir => p.join(prefixDir, 'lib');

  /// Whether [nativeLibraryDir] is a real directory we can link into.
  ///
  /// **Measured on the A54, Android 16**, with `useLegacyPackaging = false`
  /// (the AGP 8+ default, and our state until a tool ships): the path comes
  /// back real and the directory exists — it is simply **empty**, because the
  /// installer never unpacked anything. So the honest failure mode here is
  /// "directory present, files absent", which [availableLibraries] already
  /// handles by asking the filesystem per library.
  ///
  /// The `!` check guards the other documented shape (`…/base.apk!/lib/<abi>`,
  /// which `System.loadLibrary` understands and the filesystem does not). We
  /// have not seen it on this device, but it is cheap and the consequence of
  /// being wrong is a `$PATH` full of dangling entries — worse than an empty
  /// one, because the name resolves and *then* exec fails.
  bool get isUsable =>
      !nativeLibraryDir.contains('!') &&
      Directory(nativeLibraryDir).existsSync();

  /// Which of [toolset]'s libraries are actually present in this build.
  ///
  /// The flavour decides what ships, so this asks the filesystem rather than
  /// trusting the map.
  List<String> availableLibraries({
    Map<String, List<String>> toolset = defaultToolset,
  }) {
    if (!isUsable) return const [];
    final dir = Directory(nativeLibraryDir);
    if (!dir.existsSync()) return const [];
    final present = <String>[];
    for (final lib in toolset.keys) {
      if (File(p.join(nativeLibraryDir, lib)).existsSync()) present.add(lib);
    }
    return present;
  }

  /// Creates `$PREFIX/bin` and links every applet of every shipped tool.
  ///
  /// Idempotent — safe to run on every launch. Returns the applet names now
  /// on `$PATH`, so the caller can report real capability rather than a guess.
  Future<List<String>> linkBinaries({
    Map<String, List<String>> toolset = defaultToolset,
  }) async {
    final bin = Directory(binDir);
    if (!bin.existsSync()) bin.createSync(recursive: true);

    final linked = <String>[];
    for (final lib in availableLibraries(toolset: toolset)) {
      final target = p.join(nativeLibraryDir, lib);
      for (final applet in toolset[lib]!) {
        final linkPath = p.join(binDir, applet);
        try {
          final link = Link(linkPath);
          if (link.existsSync()) {
            // Re-point if the app was updated: nativeLibraryDir contains an
            // install-specific hash, so yesterday's link is stale after an
            // update and would dangle.
            if (link.targetSync() == target) {
              linked.add(applet);
              continue;
            }
            link.deleteSync();
          } else if (File(linkPath).existsSync()) {
            File(linkPath).deleteSync();
          }
          link.createSync(target);
          linked.add(applet);
        } on FileSystemException {
          // One bad applet must not abort the whole bootstrap — the rest of
          // the toolchain is still worth having.
          continue;
        }
      }
    }
    linked.sort();
    return linked;
  }

  /// Creates `$PREFIX/lib` SONAME symlinks — see [defaultLibraryAliases].
  ///
  /// Returns the SONAMEs now resolvable. Same symlink-not-copy rule as
  /// [linkBinaries], for the same reason: the bytes must stay in
  /// `nativeLibraryDir`.
  Future<List<String>> linkLibraries({
    Map<String, List<String>> aliases = defaultLibraryAliases,
  }) async {
    if (!isUsable) return const [];
    final dir = Directory(libDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final linked = <String>[];
    for (final entry in aliases.entries) {
      final target = p.join(nativeLibraryDir, entry.key);
      if (!File(target).existsSync()) continue;
      for (final soname in entry.value) {
        final linkPath = p.join(libDir, soname);
        try {
          final link = Link(linkPath);
          if (link.existsSync()) {
            if (link.targetSync() == target) {
              linked.add(soname);
              continue;
            }
            link.deleteSync();
          } else if (File(linkPath).existsSync()) {
            File(linkPath).deleteSync();
          }
          link.createSync(target);
          linked.add(soname);
        } on FileSystemException {
          continue;
        }
      }
    }
    linked.sort();
    return linked;
  }

  /// `$LD_LIBRARY_PATH` for a process we spawn from this prefix.
  ///
  /// Ours first, then `nativeLibraryDir` itself for libraries whose shipped
  /// name already matches their SONAME. Both are needed: a vendored binary's
  /// `DT_RUNPATH` points at whatever prefix its packager used (Termux's, in
  /// PRoot's case) and that directory does not exist here — `LD_LIBRARY_PATH`
  /// is searched before `DT_RUNPATH`, so this is what makes it resolve.
  String libraryPath() => '$libDir:$nativeLibraryDir';

  /// `$PATH` for a shell in this prefix.
  ///
  /// Ours first so a bundled `busybox grep` wins over the system's, then the
  /// Android system paths so `sh`, `toybox` and friends still resolve — those
  /// are system binaries and always executable.
  String pathFor({String? inherited}) {
    final parts = <String>[
      binDir,
      if (inherited != null && inherited.isNotEmpty) inherited,
      '/system/bin',
      '/system/xbin',
    ];
    // De-dup while preserving order.
    final seen = <String>{};
    return parts.where((e) => e.isNotEmpty && seen.add(e)).join(':');
  }
}
