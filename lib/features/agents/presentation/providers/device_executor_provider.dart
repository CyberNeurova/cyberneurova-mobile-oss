import 'dart:async';
import 'dart:io' show Directory, Platform, Process, ProcessSignal;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/providers/distro_install_provider.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/root_access.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_service.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/proot_runtime.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/rootfs_installer.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_backend.dart';
import 'package:cyberneurova_mobile/core/agent/device/local_network.dart';
import 'package:cyberneurova_mobile/core/agent/device/native_runtime.dart';
import 'package:cyberneurova_mobile/core/agent/device/prefix_bootstrap.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/file_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/http_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/network_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/shell_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/browser_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/apk_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/file_manage_tools.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/mdns_tools.dart';

/// What this device reports it can do.
///
/// `LOCAL_NETWORK` is claimed optimistically: on iOS 14+ the first LAN
/// connection triggers a system permission prompt, and there is no API to
/// check the answer beforehand. If the user denies it, the tools fail and say
/// so — which is more honest than withholding the capability and having the
/// agent never try.
/// Whether this device can give us a real root shell.
///
/// Detection ONLY — this never runs `su`, because doing so raises a Magisk
/// prompt, and raising one at app start before the user has asked for
/// anything trains people to tap Deny. [RootAccess.verify] is the deliberate
/// step, and it belongs behind a button.
final rootAccessProvider = FutureProvider<RootAccess>((ref) async {
  return RootAccess.detect();
});

/// Whether the ADB shell service is reachable, and how far along the user is.
///
/// Never cached across app launches: Shizuku's service dies on every reboot,
/// so a remembered "granted" would be a lie the morning after.
final shellServiceStatusProvider =
    FutureProvider<ShellServiceStatus>((ref) async => ShellService.status());

/// Whether wireless debugging has already been paired with this device.
///
/// Separate from [shellServiceStatusProvider], which reports Shizuku. The two
/// get conflated because the card that offers pairing is the one shown when
/// Shizuku is absent — so a device that WAS paired still read "shell access
/// not set up", and its Set up button opened a screen headed "Paired". The
/// state is cheap to read; asking is better than a card that contradicts the
/// screen behind it.
final adbPairedProvider =
    FutureProvider<bool>((ref) async => AdbPairing.isPaired());

/// The uid it runs as — 2000 over ADB, 0 if the user started it with root.
final shellServiceUidProvider =
    FutureProvider<int>((ref) async => ShellService.serviceUid());

/// Root the user has actually granted this session.
///
/// Separate from [rootAccessProvider] because detection and consent are
/// different facts. Nothing uses root until this says granted.
final rootGrantProvider =
    NotifierProvider<RootGrantNotifier, RootAccess>(RootGrantNotifier.new);

class RootGrantNotifier extends Notifier<RootAccess> {
  @override
  RootAccess build() => const RootAccess(status: RootStatus.unavailable);

  /// Asks for root. May show the user a prompt — only call from an explicit
  /// user action.
  Future<void> request() async {
    final found = await ref.read(rootAccessProvider.future);
    state = await RootAccess.verify(found);
  }

  void revoke() =>
      state = const RootAccess(status: RootStatus.unavailable);
}

final deviceCapabilitiesProvider = Provider<DeviceCapabilities>((ref) {
  final prefix = ref.watch(prefixBootstrapProvider).valueOrNull;
  return DeviceCapabilities(
    platform: Platform.isIOS ? 'ios' : 'android',
    osVersion: Platform.operatingSystemVersion,
    // What the shell will REALLY find on PATH this session. Recomputed rather
    // than hardcoded because, once tools arrive at runtime, this differs per
    // user and per device (`docs/shell/13-RUNTIME-INSTALL.md` §5).
    availableCommands: prefix?.applets ?? const [],
    // What the shell ACTUALLY is this session — Android's, or a distro. The
    // difference decides whether `apt`/`apk` is a real suggestion or a dead
    // end, so it must be computed, never assumed.
    installedToolsets: [
      if (ref.watch(shellBackendProvider) case final b?) b.label,
    ],
    // No delivery route is wired yet — Play Feature Delivery is the intended
    // first one. Until it exists this stays false, because an agent told it
    // can install will "fix" a missing tool by installing it, silently
    // no-op, and try again.
    // True only inside a distro, where the package manager is real. On
    // Android's shell it stays false and the agent is told not to propose apt.
    canInstallTools: ref.watch(activeDistroProvider) != null,
    // Only what this build can actually do. ICMP and packet capture still need
    // platform channels and stay MISSING until they exist — claiming a
    // capability we lack makes the agent propose a technique, fail, and retry
    // the same thing. mDNS used to be on that list and no longer is.
    present: {
      ...DeviceCapabilities.pureDartBaseline,
      // Android ships `/system/bin/sh` plus the toybox applets, and Dart can
      // spawn it — so `shell_exec` genuinely works with no bundled binary.
      // iOS never gets this: AMFI code signing is enforced in the kernel and
      // is not waivable per-app (`docs/shell/03-IOS-RUNTIME.md`), so the
      // executor refuses shell_exec there with a named missing capability
      // rather than failing obscurely at spawn time.
      if (Platform.isAndroid) DeviceCapability.execBinary,
      // Every Android phone can do this — PackageInstaller needs no root and
      // no ADB, only the user's confirmation. Whether the app has been ALLOWED
      // to ask is a separate question the tool checks at call time, because it
      // can change between turns.
      if (Platform.isAndroid) DeviceCapability.installPackages,
      // Closed by NsdDiscovery.kt. Dart cannot join a multicast group with the
      // socket options it exposes on Android, so this needed native code —
      // the reason it sat in MISSING since the capability set was written.
      if (Platform.isAndroid) DeviceCapability.mdnsDiscovery,
      // Raw sockets are the whole difference between "Kali, mostly crippled"
      // and Kali. They need real uid 0, which PRoot's `-0` only pretends to
      // be — so this appears exactly when the user has granted root and not
      // one moment earlier. Claiming it otherwise makes the model propose
      // `nmap -sS`, which fails with a permission error it cannot act on.
      if (ref.watch(rootGrantProvider).isUsable) DeviceCapability.rawSocket,
    },
  );
});

/// Root directory for shell sessions.
///
/// The app's own documents dir — the one place Android guarantees we can read
/// and write without SAF. [ShellSession] refuses to `cd` above it, so the
/// agent can't wander into paths that only produce permission errors.
final shellRootDirProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  // `home/`, not `shell/`. The user's working directory must contain only the
  // user's things: `ls` on a fresh session should print nothing, not our
  // `bin/` and `.cnrc`. Machinery lives in the sibling prefix
  // (shellPrefixDirProvider) which is on $PATH but outside the sandbox, so it
  // is reachable by name and invisible to browsing.
  final shellDir = Directory('${dir.path}/shell/home');
  if (!shellDir.existsSync()) shellDir.createSync(recursive: true);
  // Canonicalise. path_provider hands back `/data/user/0/<pkg>/…` while the
  // shell's own `$PWD` reports `/data/data/<pkg>/…` — the same directory
  // through a symlink. ShellSession stores the resolved form (it resolves
  // before its containment check), so an unresolved root here compares unequal
  // to every cwd: `cd scans` showed the full absolute path instead of
  // `~/scans`. Resolving once, at the source, keeps every consumer on one
  // spelling.
  try {
    return shellDir.resolveSymbolicLinksSync();
  } catch (_) {
    return shellDir.path;
  }
});

/// Where the machinery lives: `bin/` of tool symlinks, `etc/` of shell init.
///
/// A **sibling** of the working directory, never inside it. `ShellSession`
/// refuses to `cd` here, which is intentional — there is nothing a user or an
/// agent should be doing in it, and keeping it out of the sandbox is what lets
/// the working directory stay genuinely empty.
final shellPrefixDirProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final prefix = Directory('${dir.path}/shell/prefix');
  if (!prefix.existsSync()) prefix.createSync(recursive: true);
  try {
    return prefix.resolveSymbolicLinksSync();
  } catch (_) {
    return prefix.path;
  }
});

/// Links the bundled toolchain into `$PREFIX/bin` and reports what landed.
///
/// Runs once per app session and is cheap when nothing ships: with an empty
/// toolset it creates one directory and returns an empty list. Never throws —
/// a device with no `nativeLibraryDir` (iOS, or a channel that isn't wired)
/// just gets no bundled tools, and the shell carries on with the ~210 system
/// toybox applets it already has.
final prefixBootstrapProvider = FutureProvider<ShellPrefix>((ref) async {
  final root = await ref.watch(shellPrefixDirProvider.future);
  final libDir = await NativeRuntime.nativeLibraryDir();
  // Worth a line in logcat: when a bundled tool is "missing" on one device,
  // this is the first thing to check, and it is otherwise invisible.
  debugPrint('[pkg_core] nativeLibraryDir=$libDir');
  if (libDir == null) return ShellPrefix(prefixDir: root, applets: const []);

  final bootstrap = PrefixBootstrap(prefixDir: root, nativeLibraryDir: libDir);
  final applets = await bootstrap.linkBinaries();
  debugPrint('[pkg_core] usable=${bootstrap.isUsable} '
      'linked=${applets.length} ${applets.take(8).join(",")}');

  // The exec probes used to run HERE, awaited. Every one of them spawns a
  // process, and the Console screen cannot build until this provider settles
  // — so opening a session sat on a spinner while three processes forked.
  // They live in main.dart's post-frame diagnostic now; this provider does
  // filesystem work only.
  return ShellPrefix(
    prefixDir: root,
    applets: applets,
    libraryPath: bootstrap.libraryPath(),
    // Only override PATH when we actually linked something. `session.env`
    // REPLACES the inherited value in both consumers, and Android's real PATH
    // carries more than the two paths we'd reconstruct — `/apex/com.android.
    // runtime/bin`, `/product/bin`, `/system_ext/bin`. Overwriting it to add
    // an empty directory would quietly remove working commands.
    path: applets.isEmpty
        ? null
        : bootstrap.pathFor(inherited: Platform.environment['PATH']),
  );
});

/// Result of the bootstrap, in the shape the shell needs it.
class ShellPrefix {
  const ShellPrefix({
    required this.prefixDir,
    required this.applets,
    this.path,
    this.libraryPath,
  });

  final String prefixDir;

  /// Command names now resolvable on `$PATH` because we linked them.
  final List<String> applets;

  /// `$PATH` to hand a shell, or null when there is no bundled toolchain and
  /// the inherited one is already correct.
  final String? path;

  /// `$LD_LIBRARY_PATH` for anything we spawn — carries the SONAME symlinks
  /// plus nativeLibraryDir, so a vendored binary whose DT_RUNPATH points at
  /// its packager's prefix still resolves.
  final String? libraryPath;

  Map<String, String> get env => {
        'PREFIX': prefixDir,
        if (path != null) 'PATH': path!,
      };
}

/// Manages installed Linux distributions.
final rootfsInstallerProvider = FutureProvider<RootfsInstaller>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final prefix = await ref.watch(shellPrefixDirProvider.future);
  return RootfsInstaller(
    distrosDir: '${dir.path}/shell/distros',
    downloadsDir: '$prefix/tmp',
    // Needed for .tar.xz rootfs images; Android's tar cannot read them.
    busyboxPath: '$prefix/bin/busybox',
    libraryPath: '$prefix/lib',
    // Put a language runtime in the image at install time. See the seeding
    // stage in RootfsInstaller for why this is done here rather than left to
    // the agent — briefly: it will not do it, twice measured, and `apk add
    // --no-cache python3` costs under a minute on the device.
    seedRuntime: (distro, rootfsPath) async {
      // Read the bootstrapped prefix HERE, not as a dependency of this
      // provider.
      //
      // Watching `prefixBootstrapProvider` at provider level made this
      // provider rebuild when the bootstrap resolved — and
      // `shellWorkspaceRegistryProvider` gates on this one, so the registry
      // rebuilt too, minting fresh empty workspaces while the open terminal
      // kept the old instance. Measured: `workspace=true panes=1 lines=0` for
      // a session whose terminal was visibly full of output, which is why the
      // agent could not see the user's scrollback. The registry's own comment
      // warns about exactly this ("watching would rebuild the registry ... and
      // kill every running shell") and the seeding hook walked into it.
      final bootstrapped = await ref.read(prefixBootstrapProvider.future);
      // Run it the way `shell_exec` does, not a hand-built proot invocation.
      //
      // Two rewrites of this hook failed because it reconstructed what
      // ProotShellBackend already knows: first the library path (proot would
      // not link), then the guest PATH (apk was not found), and then it hung
      // outright — because it passed a bare argv with no `/bin/sh -c` and none
      // of the backend's binds, and Process.run waits for stdout to close.
      // The backend's own command path is exercised on every shell_exec call
      // and is verified working on device; use it.
      final backend = ProotShellBackend(
        distro: distro,
        rootfsPath: rootfsPath,
        runtime: ProotRuntime(
          prootPath: '${bootstrapped.prefixDir}/bin/proot',
          loaderPath: '${bootstrapped.prefixDir}/bin/proot-loader',
          tmpDir: '${bootstrapped.prefixDir}/tmp',
          libDir: bootstrapped.libraryPath,
        ),
        homeDir: '${dir.path}/shell/home',
      );

      final install = switch (distro.packageManager) {
        'apk' => 'apk add --no-cache python3',
        // Debian family: update first or the index is empty.
        _ => 'apt-get update -qq && '
            'apt-get install -y --no-install-recommends python3',
      };

      debugPrint('[seed] ${distro.id}: $install');
      final proc = await Process.start(
        backend.executable,
        backend.commandArgs(install, workingDir: backend.initialCwd),
        environment: backend.environment(),
      );
      // Nothing is going to type at it. An inherited stdin left open is one
      // way a package manager sits forever waiting to be answered.
      await proc.stdin.close();
      final err = StringBuffer();
      proc.stdout.listen((_) {});
      proc.stderr.listen((d) => err.write(String.fromCharCodes(d)));

      // Bounded: a convenience package must never hold setup hostage, and an
      // earlier version of this left the install stuck part-way with no distro
      // on disk.
      final code = await proc.exitCode.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          throw TimeoutException('timed out after 3 minutes; skipping python');
        },
      );
      debugPrint('[seed] exit=$code err=${err.toString().trim()}');
      if (code != 0) throw Exception('exit $code: $err');
    },
  );
});

const _kPreferredDistroKey = 'shell.preferred_distro';

/// The distro the user picked, or null for "no preference".
///
/// A preference, not a guarantee — [activeDistroProvider] resolves it against
/// what is actually on disk.
final preferredDistroProvider =
    NotifierProvider<PreferredDistroNotifier, String?>(
  PreferredDistroNotifier.new,
);

class PreferredDistroNotifier extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kPreferredDistroKey);
  }

  Future<void> select(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPreferredDistroKey, id);
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPreferredDistroKey);
  }
}

/// Which distro the shell should run in, or null for Android's own shell.
///
/// The stored preference wins **only if that distro is still installed**. A
/// stale id — the user removed it, or it failed to extract — falls back to the
/// first installed rather than refusing to start. A shell that will not open
/// because of a setting is worse than one that quietly picks something that
/// works, and the environment screen always shows which one is in use.
final activeDistroProvider = Provider<Distro?>((ref) {
  final installer = ref.watch(rootfsInstallerProvider).valueOrNull;
  if (installer == null) return null;

  final preferred = ref.watch(preferredDistroProvider);
  if (preferred != null) {
    for (final d in kDistroCatalog) {
      if (d.id == preferred && installer.isInstalled(d)) return d;
    }
  }

  // Alpine before anything else when the user has expressed no preference.
  // It is 4 MB down and 9 MB installed, so it is the one that lets the app
  // work the moment it is opened — the UserLAnd standard the owner asked for.
  // Falling back to "whatever is installed first" made a 400 MB Kali the
  // default just because it happened to be there.
  for (final d in kDistroCatalog) {
    if (d.id == kDefaultDistroId && installer.isInstalled(d)) return d;
  }

  for (final d in kDistroCatalog) {
    if (installer.isInstalled(d)) return d;
  }
  return null;
});

/// Rehomes work made before sessions had their own directories.
///
/// Runs once the registry and its backend exist, which is also the only
/// moment the guest home is knowable. Idempotent by construction — with
/// nothing loose in the home there is nothing to move — so it needs no flag
/// and cannot half-run.
final migrateLegacySessionFilesProvider = Provider<int>((ref) {
  final registry = ref.watch(shellWorkspaceRegistryProvider);
  if (registry == null) return 0;
  return registry.migrateLegacyFiles();
});

/// Installs the default distro the first time there is none.
///
/// The app should be a real Linux environment on first open, not an invitation
/// to go and choose one — that is what "works straight out of the box" means,
/// and it is only affordable because Alpine is 4 MB. Anything larger stays an
/// explicit choice in the environment screen.
///
/// Runs once per launch and only when nothing at all is installed, so it can
/// never fight a user who removed it on purpose within the same session.
final ensureDefaultDistroProvider = FutureProvider<void>((ref) async {
  final installer = await ref.watch(rootfsInstallerProvider.future);
  if (kDistroCatalog.any(installer.isInstalled)) return;

  final alpine = kDistroCatalog.firstWhere((d) => d.id == kDefaultDistroId);
  if (!alpine.isVerified) return;

  await ref.read(distroInstallProvider.notifier).install(alpine);
});

/// The backend every shell in the app runs on.
///
/// Falls back to Android's shell when no distro is installed, so the terminal
/// always works — a fresh install is usable immediately and installing Linux
/// is an upgrade, not a prerequisite.
///
/// Returns null while the prefix is still resolving.
final shellBackendProvider = Provider<ShellBackend?>((ref) {
  final prefix = ref.watch(prefixBootstrapProvider).valueOrNull;
  final home = ref.watch(shellRootDirProvider).valueOrNull;
  if (prefix == null || home == null) return null;

  final distro = ref.watch(activeDistroProvider);
  final installer = ref.watch(rootfsInstallerProvider).valueOrNull;

  // PRoot needs BOTH its binary and its loader. Checking for the loader is not
  // paranoia: without it PRoot starts, answers --version, and fails every
  // single guest exec (see tools/pkg_core/VENDORED.md).
  final hasProot = prefix.applets.contains('proot') &&
      prefix.applets.contains('proot-loader');

  if (distro != null && installer != null && hasProot) {
    return ProotShellBackend(
      distro: distro,
      rootfsPath: installer.rootfsPathFor(distro),
      runtime: ProotRuntime(
        prootPath: '${prefix.prefixDir}/bin/proot',
        loaderPath: '${prefix.prefixDir}/bin/proot-loader',
        tmpDir: '${prefix.prefixDir}/tmp',
        libDir: prefix.libraryPath,
      ),
      // The SAME directory the Android shell uses as home, bound over the
      // guest's /root. Distros come and go; the user's files do not.
      homeDir: home,
    );
  }
  return AndroidShellBackend(homeDir: home, prefixDir: prefix.prefixDir);
});

/// The tmux "server": every open shell workspace, held ABOVE the widget tree.
///
/// Deliberately not autoDispose. A workspace owns a live PTY and the shared
/// scrollback, and both must outlive the screen showing them — leaving the
/// terminal and coming back should show what happened while you were away,
/// not an empty buffer with a dead process. That detach/reattach behaviour is
/// what makes this a multiplexer rather than a terminal widget.
final shellWorkspaceRegistryProvider =
    Provider<ShellWorkspaceRegistry?>((ref) {
  final root = ref.watch(shellRootDirProvider).valueOrNull;
  if (root == null) return null;
  // Wait for the bootstrap too, so the FIRST pane already has the bundled
  // tools on $PATH. Creating panes now and fixing PATH later would mean the
  // agent's opening `which nmap` answers "no" and it picks a worse technique.
  final prefix = ref.watch(prefixBootstrapProvider).valueOrNull;
  if (prefix == null) return null;
  // Also wait for the distro check to ANSWER before creating any workspace.
  //
  // The backend is read lazily (below) so that resolving it cannot tear down
  // running shells — but that cuts both ways: a workspace created before the
  // check completes captures the Android fallback and keeps it for its whole
  // life, so an installed distro is silently ignored and the terminal comes up
  // on mksh. Gating creation on the answer costs one frame and removes the
  // race entirely.
  if (ref.watch(rootfsInstallerProvider).valueOrNull == null) return null;
  final registry = ShellWorkspaceRegistry(
    rootDir: root,
    baseEnv: prefix.env,
    // read(), not watch(): see ShellWorkspaceRegistry.backendOf — watching
    // would rebuild the registry when the distro check resolves and kill every
    // running shell.
    backendOf: () => ref.read(shellBackendProvider),
  );
  ref.onDispose(registry.killAll);
  return registry;
});

/// Get-or-create the workspace for a session id (reattach path).
final shellWorkspaceProvider =
    Provider.family<ShellWorkspace?, String>((ref, chatId) {
  if (!ref.watch(isAgentSessionProvider(chatId))) return null;
  return ref.watch(shellWorkspaceRegistryProvider)?.attach(chatId);
});

/// The shared shell context for one session — cwd and env.
///
/// **Must be the workspace's session, not a fresh one.** Handing the agent's
/// tools a different ShellSession than the terminal uses would silently break
/// the shared cwd/env invariant — `cd` on one side would be invisible to the
/// other, which is the single thing this feature is built around.
final shellSessionProvider =
    Provider.family<ShellSession?, String>((ref, chatId) {
  return ref.watch(shellWorkspaceProvider(chatId))?.shell;
});

/// Subnets the device is attached to right now.
///
/// Re-resolved rather than cached for the session: `include_local_subnet`
/// should follow the user onto a new network, and — more importantly — stop
/// authorising the old one the moment they leave it.
final localSubnetsProvider = FutureProvider<List<String>>((ref) {
  return LocalNetwork.subnets();
});

/// This device's own private IPv4 address(es).
///
/// Re-resolved rather than cached for the same reason as [localSubnetsProvider]:
/// the address follows the user onto a new network. Fed into the deviceContext
/// so the agent can answer "what's my IP" from the prompt instead of shelling
/// out for it — which does not work under PRoot and made the model loop.
final deviceSelfIpsProvider = FutureProvider<List<String>>((ref) {
  return LocalNetwork.selfPrivateIps();
});

/// Per-chat authorized scope.
///
/// Defaults to empty, which per `docs/shell/06-AGENT-INTEGRATION.md` §3.3
/// means only the device itself is targetable. That is a safe default and a
/// deliberate one: the agent can explore without the user having handed it
/// anything, and every widening is an explicit act.
final sessionScopeProvider =
    NotifierProvider.family<SessionScopeNotifier, AuthorizedScope, String>(
  SessionScopeNotifier.new,
);

class SessionScopeNotifier extends FamilyNotifier<AuthorizedScope, String> {
  @override
  AuthorizedScope build(String chatId) => const AuthorizedScope.empty();

  /// Replaces the scope. The caller is expected to have shown the user
  /// exactly what they are authorising — this is not a silent widening.
  void declare(AuthorizedScope scope) => state = scope;

  void clear() => state = const AuthorizedScope.empty();
}

/// The sections whose sessions may run device tools.
///
/// All three agent surfaces, by the owner's decision (2026-08-03): the point
/// of the agent surfaces is that work happens on the user's device, so Code
/// can build an app and launch a server on the phone, and Research can use
/// the device's own network rather than ours.
///
/// An ordinary chat is deliberately NOT here. A plain conversation reaching
/// the user's filesystem and LAN is a different product, and the section tag
/// is the only thing separating them.
const _deviceToolSections = {
  AppConstants.sectionShell,
  AppConstants.sectionCode,
  AppConstants.sectionResearch,
};

/// Whether this session may run device tools at all.
///
/// Defaults to false while the chat list is still loading: unknown must mean
/// "no device tools", never "probably fine".
final isAgentSessionProvider = Provider.family<bool, String>((ref, chatId) {
  final chats = ref.watch(chatListProvider).valueOrNull;
  if (chats == null) return false;
  for (final c in chats) {
    if (c.id == chatId) {
      return _deviceToolSections.contains(c.section);
    }
  }
  return false;
});

/// Which agent surface this session belongs to, or null for a plain chat.
///
/// Null is load-bearing: it is how every caller distinguishes "this session can
/// act on the device" from "this one cannot", without re-deriving it from the
/// section string in four places.
final agentSurfaceProvider =
    Provider.family<AgentSurface?, String>((ref, chatId) {
  final chats = ref.watch(chatListProvider).valueOrNull;
  if (chats == null) return null;
  for (final c in chats) {
    if (c.id == chatId) return AgentSurface.forSection(c.section);
  }
  return null;
});

/// The device executor for one session, or **null** when the session is not
/// permitted to run device tools.
///
/// Where it is non-null this is the load-shedding path: the server
/// orchestrates (cheap — mostly waiting on the model) while scans and LAN
/// probes run here, reaching a network a server-side container never can.
///
/// Rebuilt when scope or the local subnets change, so a network switch or a
/// scope edit takes effect on the next call rather than the next session.
final deviceExecutorProvider =
    Provider.family<DeviceExecutor?, String>((ref, chatId) {
  if (!ref.watch(isAgentSessionProvider(chatId))) return null;

  final shellSession = ref.watch(shellSessionProvider(chatId));

  return DeviceExecutor(
    capabilities: ref.watch(deviceCapabilitiesProvider),
    scope: ref.watch(sessionScopeProvider(chatId)),
    localSubnetCidrs: ref.watch(localSubnetsProvider).valueOrNull ?? const [],
    tools: [
      NetDiscoverTool(),
      // Names what a scan can only number. Android only — it needs
      // NsdManager, which is exactly why MDNS_DISCOVERY was MISSING.
      if (Platform.isAndroid) const MdnsDiscoverTool(),
      NetScanTool(),
      DnsQueryTool(),
      HttpProbeTool(),
      // The browser, not just a fetch: a large share of the web returns an
      // empty shell and builds its content in JavaScript, so http_probe
      // reports "blank page" for pages a person can plainly read.
      BrowserOpenTool(),
      // File tools are pure Dart and work on BOTH platforms — the phone's own
      // container is readable on iOS even though executing binaries is not.
      if (shellSession != null) ...[
        FileListTool(session: shellSession),
        FileReadTool(session: shellSession),
        FileWriteTool(session: shellSession),
        // Creating files without being able to move or remove them leaves a
        // session accumulating scratch output it cannot clean, with shell_exec
        // rm as the only remedy — unavailable on iOS and a blunt instrument to
        // hand a model.
        FileMoveTool(session: shellSession),
        FileDeleteTool(session: shellSession),
        FileMkdirTool(session: shellSession),
      ],
      // Only offered once the session root resolved, and only where a shell
      // actually exists. Registering it on iOS would put `shell_exec` in the
      // advertised tool list for a platform that can never run it.
      // Closes the loop from "the agent produced an APK" to "it is on the
      // phone". Android only, and the user confirms every one — see
      // ApkInstallTool.
      if (shellSession != null && Platform.isAndroid)
        ApkInstallTool(session: shellSession),
      if (shellSession != null && Platform.isAndroid)
        ShellExecTool(
          session: shellSession,
          // MUST be the same backend the terminal uses, or the agent would be
          // operating on a different filesystem than the user is looking at.
          backend: ref.watch(shellBackendProvider),
          // Agent commands land in the SAME scrollback the user reads, marked
          // as agent-issued. Without this the agent works invisibly and the
          // user has no way to check it.
          onRecord: ref.watch(shellWorkspaceProvider(chatId))?.active
              .recordAgentCommand,
        ),
    ],
  );
});

/// The capability block to send as `deviceContext`, or null when this session
/// has no device executor.
///
/// Regenerated per turn on purpose. Every line in it can change between one
/// message and the next — the working directory moves, the user installs a
/// distro, they join a different network, they widen the authorized scope — and
/// a stale block is worse than none: it makes the model confident about a
/// device that no longer looks like that.
///
/// Null for non-shell chats, which also matches the server gate (chat-team
/// inbox/032 honours it only when `section === "shell"`), so an ordinary chat
/// never carries a description of the user's filesystem.
final deviceContextProvider = Provider.family<String?, String>((ref, chatId) {
  if (!ref.watch(isAgentSessionProvider(chatId))) return null;

  final caps = ref.watch(deviceCapabilitiesProvider);
  final session = ref.watch(shellSessionProvider(chatId));
  final backend = ref.watch(shellBackendProvider);

  // What this surface is FOR goes above what the device can DO. Kept apart on
  // purpose: the device facts below change between turns, this does not — and
  // a model given only a tool list will invent the job it thinks it has.
  final surface = ref.watch(agentSurfaceProvider(chatId));

  final block = caps.promptBlock(
    scope: ref.watch(sessionScopeProvider(chatId)),
    cwd: session?.cwd,
    localSubnetCidrs: ref.watch(localSubnetsProvider).valueOrNull ?? const [],
    // The device's own address, so "what's my IP" is answered from the prompt
    // rather than through a shell that cannot see the network under PRoot.
    selfIps: ref.watch(deviceSelfIpsProvider).valueOrNull ?? const [],
    // Whether the shell is a PRoot guest — decides the SHELL/BASE-TOOLS line and
    // the network-introspection warning.
    underProot: backend?.hasFakeRoot ?? false,
  );

  // PRoot reports uid=0 and it is a convincing lie. Said plainly here because
  // it is the single most common wrong assumption about the environment: a
  // model that believes it is root proposes `nmap -sS`, watches it fail on the
  // raw socket, and proposes it again.
  final notRoot = (backend?.hasFakeRoot ?? false)
      ? '\nNOT ROOT: the shell reports uid=0 but has no kernel capability. '
          'SYN scans (`nmap -sS`), packet capture and monitor mode WILL fail. '
          'Use a connect scan (`nmap -sT`).'
      : '';

  final preamble = surface == null ? '' : '${surface.promptBlock}\n\n';
  return '$preamble$block$notRoot';
});

/// Whether a downloaded distribution can actually RUN on this build.
///
/// False on the Play flavour: SELinux forbids executing a file the app wrote,
/// so a rootfs would download, verify, extract — and then refuse to run a
/// single binary. Gating the UI on this is the difference between a clear
/// explanation and a user losing 400 MB of data to find out.
///
/// Derived from the measurement rather than the flavour name, so it stays true
/// if the packaging ever changes (`docs/shell/14-FLAVOURS.md`).
/// Whether this build can run a downloaded Linux distribution.
///
/// This used to probe whether a file written into app data could be exec'd,
/// and concluded "no" on any build targeting API 29+. That was the wrong
/// question, and it cost the Play build the whole feature for no reason.
///
/// PRoot never execs a guest binary that way. PRoot itself runs from
/// `nativeLibraryDir`, which stays executable at every targetSdk, and its
/// loader maps the guest ELF into anonymous memory — which is permitted, as
/// the `ExecMemory.probeAnonymousExec` spike showed. The W^X restriction bans
/// `execve` of an app_data_file; it does not ban running a guest under PRoot.
///
/// Verified on a Samsung SM-A546E, Android 16, play flavour at targetSdk 36:
/// Alpine 3.21.7 boots, `id` reports uid=0, and `apk add tree` fetches from
/// Alpine's CDN and installs. This is the same mechanism UserLAnd uses.
///
/// So the real question is only whether the PRoot binaries shipped. Keep the
/// file-exec probe for diagnostics — it reports something true — but never
/// gate distro support on it again.
final canInstallDistrosProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  final prefix = await ref.watch(prefixBootstrapProvider.future);
  // Both halves: without the loader PRoot starts, answers --version, and
  // fails every guest exec (tools/pkg_core/VENDORED.md).
  return prefix.applets.contains('proot') &&
      prefix.applets.contains('proot-loader');
});
