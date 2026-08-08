import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the device's connectivity status. Emits `true` when ANY usable
/// connection is available (wifi, mobile, ethernet, vpn), `false` for `none`.
///
/// We watch this globally so the UI can show an offline banner instantly
/// without waiting for an API call to fail.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  // Emit the current state immediately, then stream updates.
  yield _isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) {
  if (results.isEmpty) return false;
  // ConnectivityResult.none is the only "offline" state.
  return results.any((r) => r != ConnectivityResult.none);
}

/// True if the device is currently offline. Defaults to true (assume online)
/// while the very first connectivity check is in flight, so we don't flash
/// the banner on cold start.
final isOfflineProvider = Provider<bool>((ref) {
  final state = ref.watch(connectivityProvider);
  return state.maybeWhen(
    data: (online) => !online,
    orElse: () => false,
  );
});
