import 'dart:async';
import 'package:dio/dio.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';

/// Attaches the Bearer token to every request and transparently refreshes it
/// on a 401 response (single retry, no infinite loops).
///
/// **Concurrency:** if multiple requests fail with 401 at the same time,
/// they all share a single refresh future via `_refreshLock`. Without this,
/// each 401 would fire its own `/auth/refresh` and — since chat-team rotates
/// the refresh token on use — all but the first would 401 again and log the
/// user out spuriously.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.dio,
    this.onAccessTokenChanged,
  });

  final SecureStorage storage;
  final Dio dio;

  /// Hook fired whenever the access token rotates (login, refresh, logout)
  /// so out-of-band consumers — currently the synchronous
  /// `currentAccessTokenProvider` mirror that `AuthedNetworkImage` reads
  /// — can stay in sync without polling secure storage.
  final void Function(String? token)? onAccessTokenChanged;

  /// Shared refresh future. While non-null, any subsequent 401 awaits it
  /// instead of firing its own refresh.
  Future<String?>? _refreshLock;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] == true) {
      return handler.next(options);
    }

    final token = await storage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) return handler.next(err);

    // Prevent retry loop on the refresh endpoint itself
    if (err.requestOptions.path.contains(ApiConstants.AUTH_REFRESH)) {
      await storage.clearAll();
      return handler.next(err);
    }

    // Either start a new refresh or piggyback on the in-flight one.
    final newAccess = await (_refreshLock ??= _doRefresh());
    if (newAccess == null) {
      // Refresh failed — storage was cleared, downstream will see 401.
      return handler.next(err);
    }

    try {
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retried = await dio.fetch(err.requestOptions);
      return handler.resolve(retried);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Performs the actual refresh. Returns the new access token, or null on
  /// failure. Clears `_refreshLock` when done so subsequent 401s start fresh.
  Future<String?> _doRefresh() async {
    try {
      final refreshToken = await storage.getRefreshToken();
      if (refreshToken == null) return null;

      final res = await dio.post(
        ApiConstants.AUTH_REFRESH,
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );

      final newAccess = res.data['accessToken'] as String;
      final newRefresh = res.data['refreshToken'] as String;
      await storage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      onAccessTokenChanged?.call(newAccess);
      return newAccess;
    } catch (_) {
      await storage.clearAll();
      onAccessTokenChanged?.call(null);
      return null;
    } finally {
      _refreshLock = null;
    }
  }
}
