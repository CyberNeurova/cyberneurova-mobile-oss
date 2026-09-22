import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/features/remote/data/models/remote_device.dart';
import 'package:cyberneurova_mobile/features/remote/data/repositories/remote_control_repository.dart';

/// The user's ONLINE devices (filtered per spec: an offline device can't run a
/// session). Auto-disposes so the list is a fresh read each time the screen
/// opens.
final remoteDevicesProvider =
    FutureProvider.autoDispose<List<RemoteDevice>>((ref) async {
  final all = await ref.read(remoteControlRepositoryProvider).listDevices();
  return [for (final d in all) if (d.online) d];
});
