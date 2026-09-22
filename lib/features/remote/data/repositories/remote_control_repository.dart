import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/remote/data/models/remote_device.dart';

final remoteControlRepositoryProvider = Provider<RemoteControlRepository>((ref) {
  return RemoteControlRepository(ref.watch(apiClientProvider));
});

/// Client for the Remote Control relay — mobile as the CONTROLLER attaching to
/// a running desktop/CLI session. Two calls (chat spec `mobile/chat/…-0840`):
///
///  1. [listDevices] — the user's online devices, each with a precomputed
///     `attach_url`.
///  2. [createSession] — mint a relay session for a device and return the
///     `cnrc_session` COOKIE VALUE from the body (a Flutter webview has its own
///     cookie jar, so `Set-Cookie` won't reach it — we inject this before
///     loading `attach_url`).
///
/// SCAFFOLD: the relay isn't built yet (chat builds it after desktop freezes
/// the 005 protocol), so these calls fail until it's live. The auth/base path
/// is pending confirmation on wiring — the mobile [ApiClient] attaches the
/// mobile JWT and prefixes `/api/mobile/v1`; the spec wrote the engine-side
/// `cnat_`/`/v1/remote/*` shape, which the proxy maps to.
class RemoteControlRepository {
  RemoteControlRepository(this._client);

  final ApiClient _client;

  Future<List<RemoteDevice>> listDevices() async {
    final res = await _client.get(ApiConstants.REMOTE_DEVICES);
    return RemoteDevice.listFrom(res.data);
  }

  /// Returns the `cnrc_session` cookie value to inject into the webview jar,
  /// or null if the body didn't carry one.
  Future<String?> createSession(String deviceId) async {
    final res = await _client.post(
      ApiConstants.REMOTE_SESSION,
      data: {'device_id': deviceId},
    );
    final data = res.data;
    final cookie = data is Map ? data['cookie'] : null;
    return cookie is String && cookie.isNotEmpty ? cookie : null;
  }
}
