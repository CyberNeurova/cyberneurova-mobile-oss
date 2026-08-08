import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';

/// Fire-and-forget analytics — events are buffered server-side and flushed
/// to PG on a 1s tick. Per the backend API: clients SET `event_type`
/// + optional metadata; the server stamps user / IP / country / city.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(apiClientProvider));
});

class AnalyticsRepository {
  AnalyticsRepository(this._client);
  final ApiClient _client;

  String? _cachedVersion;

  Future<String> _appVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      return _cachedVersion = info.version;
    } catch (_) {
      return _cachedVersion = '0.0.0';
    }
  }

  /// Single event. Most common path for thumbs / button taps. For high-volume
  /// flushes (e.g. offline queue replay) use [trackBatch].
  Future<void> track({
    required String eventType,
    String? category,
    String? page,
    int? durationMs,
    String? toolName,
    String? modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final version = await _appVersion();
      await _client.post<Map<String, dynamic>>(
        ApiConstants.ANALYTICS_EVENTS,
        data: {
          'event_type': eventType,
          if (category != null) 'category': category,
          if (page != null) 'page': page,
          if (durationMs != null) 'duration_ms': durationMs,
          if (toolName != null) 'tool_name': toolName,
          if (modelName != null) 'model_name': modelName,
          if (metadata != null) 'metadata': metadata,
          'app_platform': 'mobile',
          'app_version': version,
          'os_family': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (_) {
      // Analytics failures are silent — never surface to the user.
      // The server's a fire-and-forget endpoint by design.
    }
  }
}
