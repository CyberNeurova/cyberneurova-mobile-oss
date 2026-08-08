import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/rootfs_installer.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';

/// What the UI needs to draw for one distro.
class DistroState {
  const DistroState({
    required this.distro,
    required this.installed,
    this.progress,
  });

  final Distro distro;
  final bool installed;

  /// Non-null while an install is running or has just failed.
  final InstallProgress? progress;

  bool get isVerified => distro.isVerified;

  bool get isBusy =>
      progress != null && !progress!.isTerminal;

  String? get error =>
      progress?.stage == InstallStage.failed ? progress?.message : null;
}

/// Drives distro installs and exposes their progress.
///
/// Deliberately **not** autoDispose. A 400 MB Kali download must survive the
/// user navigating away — a install that silently dies because they opened
/// another screen is worse than one that never started, and on a phone people
/// switch away constantly while something downloads.
final distroInstallProvider =
    NotifierProvider<DistroInstallNotifier, Map<String, InstallProgress>>(
  DistroInstallNotifier.new,
);

class DistroInstallNotifier extends Notifier<Map<String, InstallProgress>> {
  final _running = <String, StreamSubscription<InstallProgress>>{};

  @override
  Map<String, InstallProgress> build() {
    ref.onDispose(() {
      for (final s in _running.values) {
        s.cancel();
      }
      _running.clear();
    });
    return const {};
  }

  bool isBusy(String id) => _running.containsKey(id);

  Future<void> install(Distro distro) async {
    // Re-entrancy guard: tapping Install twice would run two downloads into
    // the same temp file and the second would corrupt the first's hash.
    if (_running.containsKey(distro.id)) return;

    final installer = await ref.read(rootfsInstallerProvider.future);
    _running[distro.id] = installer.install(distro).listen(
      (ev) {
        state = {...state, distro.id: ev};
        if (ev.isTerminal) {
          _running.remove(distro.id)?.cancel();
          // A finished install changes which backend new shells get, so the
          // catalogue and the executor both need to re-read the filesystem.
          ref.invalidate(rootfsInstallerProvider);
        }
      },
      onError: (Object e) {
        state = {
          ...state,
          distro.id: InstallProgress(
            stage: InstallStage.failed,
            // Rendered on the Agent environment screen. This was `'$e'`, so a
            // failed distro install showed the user a Dart exception in the
            // middle of a setup flow. No BuildContext here, so the server's
            // own wording is used when it reads like a sentence.
            message: installFailureMessage(e),
          ),
        };
        _running.remove(distro.id)?.cancel();
      },
    );
  }

  /// Cancels an in-flight install. The partial download is left in the temp
  /// directory and overwritten by the next attempt — never promoted, because
  /// [RootfsInstaller] verifies before it extracts.
  void cancel(String id) {
    _running.remove(id)?.cancel();
    state = {...state}..remove(id);
  }

  Future<void> remove(Distro distro) async {
    final installer = await ref.read(rootfsInstallerProvider.future);
    await installer.remove(distro);
    state = {...state}..remove(distro.id);
    ref.invalidate(rootfsInstallerProvider);
  }
}

/// The catalogue, each entry carrying its installed and in-flight state.
final distroListProvider = Provider<List<DistroState>>((ref) {
  final installer = ref.watch(rootfsInstallerProvider).valueOrNull;
  final progress = ref.watch(distroInstallProvider);
  return [
    for (final d in kDistroCatalog)
      DistroState(
        distro: d,
        installed: installer?.isInstalled(d) ?? false,
        progress: progress[d.id],
      ),
  ];
});

/// What to show when a distro install fails.
///
/// No `BuildContext` is available in a provider, so this cannot go through
/// `userMessageFor`. It applies the same rule by hand: prefer the server's
/// wording when it reads like a sentence, and never hand the user a runtime
/// error — `isTechnicalErrorMessage` knows the shapes ("fetch failed",
/// `ECONN*`, `SocketException`, and friends).
String installFailureMessage(Object e) {
  final raw = e is AppException ? e.message : e.toString();
  return isTechnicalErrorMessage(raw)
      ? 'The download failed. Check your connection and try again.'
      : raw;
}
