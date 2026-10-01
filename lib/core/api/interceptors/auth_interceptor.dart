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
///
/// **Failed refresh:** only the refresh endpoint answering 400/401/403 ends
/// the session. A refresh that got no verdict — no network, a timeout, a 5xx,
/// a 429 — keeps both tokens and fails just this request with that error, so
/// the user stays signed in and the next 401 tries the refresh again.
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

    // This request already went out again with a freshly refreshed token and
    // was still refused, so the 401 is about something other than an expired
    // token. Refreshing again would rotate the tokens and be refused again,
    // round and round — pass it on instead.
    if (err.requestOptions.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    // Either start a new refresh or piggyback on the in-flight one.
    final String? newAccess;
    try {
      newAccess = await (_refreshLock ??= _doRefresh());
    } on DioException catch (refreshErr) {
      // The refresh got no verdict on the token (no network, a timeout, a
      // 5xx, a 429). The tokens are untouched, so fail with what actually
      // went wrong — ErrorInterceptor turns it into NetworkException,
      // ServiceUnavailableException, ... — rather than the 401, which callers
      // read as "signed out".
      return handler.next(refreshErr);
    } catch (e) {
      // Not a rejection of the session either (an unreadable refresh
      // response, a storage hiccup). The tokens stay, so the original 401
      // must not go on — at cold start AuthNotifier reads it as signed out —
      // and this request fails with what actually went wrong instead.
      return handler.next(DioException(
        requestOptions: err.requestOptions,
        error: e,
        type: DioExceptionType.unknown,
      ));
    }
    if (newAccess == null) {
      // No refresh token to use, or the server rejected it (storage was
      // cleared) — either way there is no session, downstream sees the 401.
      return handler.next(err);
    }

    try {
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      err.requestOptions.extra[_retriedKey] = true;
      final retried = await dio.fetch(err.requestOptions);
      return handler.resolve(retried);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Performs the actual refresh. Returns the new access token, or null when
  /// there is nothing to refresh or the server rejected the refresh token (in
  /// which case storage is cleared). Any other failure is rethrown with the
  /// tokens left in place. Clears `_refreshLock` when done so subsequent 401s
  /// start fresh.
  Future<String?> _doRefresh() async {
    try {
      final refreshToken = await storage.getRefreshToken();
      if (refreshToken == null) return null;

      final Response<dynamic> res;
      try {
        res = await dio.post(
          ApiConstants.AUTH_REFRESH,
          data: {'refreshToken': refreshToken},
          options: Options(extra: {'skipAuth': true}),
        );
      } on DioException catch (e) {
        // Only the endpoint itself saying no means the refresh token is dead.
        // A dropped connection, a timeout, a deploy's 502 or a rate limit
        // says nothing about it, and wiping it would force a fresh sign-in.
        if (!_rejectionStatuses.contains(e.response?.statusCode)) rethrow;
        await storage.clearAll();
        onAccessTokenChanged?.call(null);
        return null;
      }

      final newAccess = res.data['accessToken'] as String;
      // A server that does not rotate refresh tokens sends none back; the
      // current one is still the one to use.
      final newRefresh = res.data['refreshToken'] as String? ?? refreshToken;
      await storage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      onAccessTokenChanged?.call(newAccess);
      return newAccess;
    } finally {
      _refreshLock = null;
    }
  }

  /// Marks a request that was already retried with a refreshed token.
  static const _retriedKey = 'authRetried';

  /// Refresh responses that mean the refresh token is no longer accepted.
  static const _rejectionStatuses = {400, 401, 403};
}
