import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'dart:async';
import 'dart:io' show Directory, Process;

import 'package:path_provider/path_provider.dart';
import 'package:cyberneurova_mobile/app/app.dart';
import 'package:cyberneurova_mobile/core/agent/device/exec_memory.dart';
import 'package:cyberneurova_mobile/core/constants/dev_flags.dart';
import 'package:cyberneurova_mobile/core/agent/device/native_runtime.dart';
import 'package:cyberneurova_mobile/core/agent/device/prefix_bootstrap.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/proot_runtime.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/rootfs_installer.dart';

void main() async {
  // Must be called before FlutterNativeSplash.preserve
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Keep the native splash visible until the app is ready
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Edge-to-edge on Android 10+; iOS handles this via SafeArea
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Transparent bars — content draws behind them, SafeArea insets handle layout
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,         // Android
      statusBarBrightness: Brightness.dark,               // iOS
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Phones: lock to portrait. Chat apps don't benefit from landscape on
  // small screens; the input/keyboard layout breaks.
  // Tablets (iPad, large Android): allow all orientations. Apple's review
  // team has rejected portrait-locked iPad apps before, and iPads are
  // commonly held in landscape.
  final view = binding.platformDispatcher.views.first;
  final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
  final isTablet = shortestSide >= 600;
  await SystemChrome.setPreferredOrientations(
    isTablet
        ? const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
  );

  // Diagnostics must NEVER block the first frame.
  //
  // This was `await`ed here, which put a MethodChannel round-trip, symlink
  // work and four to six Process.run spawns (proot --version, getprop, two
  // exec probes) in front of runApp. On a phone that is a visibly blank
  // screen before the app has drawn anything — the "takes forever to load"
  // the owner reported. Nothing in the UI reads these; they only print.
  //
  // Fire-and-forget after the first frame instead.
  // Post-frame was not far enough. Linking nine binaries and spawning proot
  // takes ~600ms, and doing it while the launch animation is still playing is
  // a visible stutter on open — reported by the owner, measured at 590ms of
  // file and process work starting 250ms after the first frame. It only ever
  // printed, and its answer is already in docs/shell/SPIKE-RESULTS.md, so it
  // is now opt-in for the rare case where the question is open again.
  // Linking the toolchain is SETUP, not diagnostics — proot cannot start
  // without `libtalloc.so.2` sitting next to it, so this must always run. I
  // gated the whole function behind a dev flag on the strength of its name and
  // its logging, and broke the shell for one build: "CANNOT LINK EXECUTABLE
  // .../proot: library libtalloc.so.2 not found". The measurement half is the
  // part nobody needs at launch, and that is what the flag now controls.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_bootstrapToolchain(measure: probeBundledTools));
  });

  runApp(
    const ProviderScope(
      child: CyberNeuropvaApp(
        onReady: FlutterNativeSplash.remove,
      ),
    ),
  );
}

/// Links the bundled toolchain, and optionally measures whether it runs.
///
/// Two jobs that used to be one function, which is how gating "the probe" also
/// removed the linking and left proot unable to load `libtalloc.so.2`:
///
///  - **Always:** symlink the applets and shared libraries into `$PREFIX`.
///    Nothing else does this, and the Linux runtime is dead without it.
///  - **[measure] only:** spawn proot and run the two exec probes. That is the
///    measurement behind `docs/shell/13-RUNTIME-INSTALL.md` route A — whether
///    a `lib*.so` in `nativeLibraryDir` can be exec'd through a `$PREFIX/bin`
///    symlink — and its answer is already recorded in SPIKE-RESULTS.md. It
///    costs ~600ms of process work during the launch animation, so it is
///    opt-in via `--dart-define=PROBE_BUNDLED_TOOLS=true`.
Future<void> _bootstrapToolchain({required bool measure}) async {
  try {
    final libDir = await NativeRuntime.nativeLibraryDir();
    if (libDir == null) {
      debugPrint('[startup] no nativeLibraryDir (not Android?)');
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final prefix = Directory('${docs.path}/shell/prefix');
    if (!prefix.existsSync()) prefix.createSync(recursive: true);

    final boot = PrefixBootstrap(
      prefixDir: prefix.resolveSymbolicLinksSync(),
      nativeLibraryDir: libDir,
    );
    final applets = await boot.linkBinaries();
    final sonames = await boot.linkLibraries();
    debugPrint('[startup] linked=${applets.length} $applets libs=$sonames');

    if (!measure) return;

    // Does the VENDORED proot actually run here? Termux built it for their
    // prefix and their toolchain, so this is measured, not assumed — the same
    // loop that caught a TLS-alignment failure in our own binary.
    if (applets.contains('proot')) {
      try {
        // PROOT_TMP_DIR must exist — PRoot extracts its loader there and
        // Android has no /tmp to fall back on.
        final tmp = Directory('${boot.prefixDir}/tmp');
        if (!tmp.existsSync()) tmp.createSync(recursive: true);
        final r = await Process.run(
          '${boot.binDir}/proot',
          ['--version'],
          environment: {
            'LD_LIBRARY_PATH': boot.libraryPath(),
            'PROOT_TMP_DIR': tmp.path,
          },
        );
        final line =
            '${r.stdout}${r.stderr}'.trim().split('\n').first;
        debugPrint('[startup] proot exit=${r.exitCode} :: $line');
      } catch (e) {
        debugPrint('[startup] proot FAILED: $e');
      }
    }
    // One-shot end-to-end check of the Linux path, opt-in via:
    //   adb shell setprop debug.cn.installAlpine 1
    // Behind a property because it is a 3.7 MB download and nobody wants that
    // on every launch. Remove once the distro UI exists.
    if (applets.contains('proot')) await _tryAlpine(boot);

    debugPrint('[startup] bundled-exec='
        '${await ExecMemory.probeBundledExec(boot.binDir, 'cn-hello')}');
    // The flavour question: can this build execute a file it WROTE? `direct`
    // (targetSdk 28) must say OK — that is the only reason the flavour exists,
    // because it is what a downloaded rootfs needs. `play` must say denied.
    debugPrint('[startup] downloaded-exec='
        '${await ExecMemory.probeFileExec(boot.prefixDir) ?? "OK"}');
  } catch (e) {
    debugPrint('[startup] probe failed: $e');
  }
}

/// End-to-end proof of the Linux path: install Alpine, then run something
/// inside it under PRoot. Gated on a system property, opt-in.
Future<void> _tryAlpine(PrefixBootstrap boot) async {
  try {
    final flag = await Process.run('/system/bin/getprop',
        ['debug.cn.installAlpine']);
    if ('${flag.stdout}'.trim() != '1') return;

    final docs = await getApplicationDocumentsDirectory();
    final installer = RootfsInstaller(
      distrosDir: '${docs.path}/shell/distros',
      downloadsDir: '${docs.path}/shell/prefix/tmp',
    );
    final alpine = kDistroCatalog.firstWhere((d) => d.id == 'alpine');

    if (!installer.isInstalled(alpine)) {
      await for (final ev in installer.install(alpine)) {
        if (ev.stage == InstallStage.downloading && ev.fraction != null) {
          continue; // too chatty for logcat
        }
        debugPrint('[alpine] ${ev.stage.name}: ${ev.message ?? ""}');
      }
    } else {
      debugPrint('[alpine] already installed');
    }
    if (!installer.isInstalled(alpine)) return;

    // The real test: run a guest binary inside the rootfs, under PRoot.
    final rt = ProotRuntime(
      prootPath: '${boot.binDir}/proot',
      tmpDir: '${boot.prefixDir}/tmp',
      loaderPath: '${boot.binDir}/proot-loader',
      libDir: boot.libraryPath(),
    );
    final r = await Process.run(
      rt.prootPath,
      rt.argsFor(
        rootfs: installer.rootfsPathFor(alpine),
        command: ['/bin/sh', '-c', 'cat /etc/alpine-release; id; uname -m'],
      ),
      environment: {...rt.processEnv, ...rt.guestEnv()},
    );
    debugPrint('[alpine] proot exit=${r.exitCode}');
    for (final l in '${r.stdout}${r.stderr}'.trim().split('\n').take(6)) {
      debugPrint('[alpine]   $l');
    }
    installer.dispose();
  } catch (e) {
    debugPrint('[alpine] FAILED: $e');
  }
}
