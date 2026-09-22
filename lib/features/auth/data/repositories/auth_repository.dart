import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/terms_model.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
    ref,
  );
});

class AuthRepository {
  AuthRepository(this._client, this._storage, this._ref);
  final ApiClient _client;
  final SecureStorage _storage;
  final Ref _ref;

  /// Mirror the just-saved access token into currentAccessTokenProvider
  /// so widgets reading it synchronously (e.g. AuthedNetworkImage) get
  /// the token without a FutureBuilder.
  Future<void> _saveAndMirror({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    _ref.read(currentAccessTokenProvider.notifier).state = accessToken;
  }

  // ─── Email / password ─────────────────────────────────────────────────────

  Future<AuthTokensModel> login({
    required String email,
    required String password,
    String? deviceToken,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.AUTH_LOGIN,
      data: {
        'email': email,
        'password': password,
        if (deviceToken != null) 'deviceToken': deviceToken,
      },
    );
    final tokens = AuthTokensModel.fromJson(res.data!);
    await _saveAndMirror(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return tokens;
  }

  /// Registers a new account. Response does NOT contain tokens — the user
  /// must verify email first, then call [login]. Requires ToS acceptance
  /// per chat-team's inbox/006 — server returns 400 TOS_NOT_ACCEPTED
  /// or 409 TOS_VERSION_OUTDATED otherwise.
  Future<RegisterResponse> register({
    required String email,
    required String password,
    required String tosVersion,
    String? fullName,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.AUTH_REGISTER,
      data: {
        'email': email,
        'password': password,
        'tosAccepted': true,
        'tosVersion': tosVersion,
        if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
      },
    );
    return RegisterResponse.fromJson(res.data!);
  }

  /// Fetches the current Terms of Service version + canonical URLs.
  /// Public endpoint, no auth. Cache locally; re-fetch on every register
  /// screen mount so a long-lived install doesn't ship stale text.
  Future<TermsInfo> fetchCurrentTerms() async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.LEGAL_TERMS,
    );
    return TermsInfo.fromJson(res.data!);
  }

  // ─── OAuth ────────────────────────────────────────────────────────────────

  Future<AuthTokensModel> loginWithGoogle(String idToken) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.AUTH_GOOGLE,
      data: {'idToken': idToken},
    );
    final tokens = AuthTokensModel.fromJson(res.data!);
    await _saveAndMirror(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return tokens;
  }

  /// Sign in with Apple. On FIRST auth Apple returns email + name; cache them.
  /// On subsequent auths Apple omits them — pass [email] from your local cache.
  /// If [email] is null on a non-first auth, server returns 400 APPLE_NO_EMAIL.
  Future<AuthTokensModel> loginWithApple({
    required String idToken,
    String? nonce,
    String? email,
    String? firstName,
    String? lastName,
    String? authorizationCode,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.AUTH_APPLE,
      data: {
        'idToken': idToken,
        if (nonce != null) 'nonce': nonce,
        if (email != null) 'email': email,
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (authorizationCode != null) 'authorizationCode': authorizationCode,
      },
    );
    final tokens = AuthTokensModel.fromJson(res.data!);
    await _saveAndMirror(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return tokens;
  }

  // ─── Session lifecycle ────────────────────────────────────────────────────

  Future<UserModel> getMe() async {
    final res = await _client.get<Map<String, dynamic>>(ApiConstants.AUTH_ME);
    // /auth/me returns {user: {...}}
    final data = res.data!;
    // Sahachiel: `as Map? ?? data` survives a null/missing user, but a present
    // non-map ({"user": "x"} / 123) still threw - guard with `is Map`. /auth/me
    // runs on every cold start, so a CastError here bricks launch.
    final userJson = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : data;
    return UserModel.fromJson(userJson);
  }

  Future<void> logout() async {
    try {
      await _client.post(ApiConstants.AUTH_LOGOUT);
    } catch (_) {
      // Best-effort server logout — a network failure here must not propagate
      // (callers fire it unawaited); tokens are cleared below regardless so the
      // user is always logged out client-side.
    } finally {
      await _storage.clearAll();
      _ref.read(currentAccessTokenProvider.notifier).state = null;
    }
  }

  Future<bool> hasSession() async {
    final token = await _storage.getAccessToken();
    // Rehydrate the synchronous mirror on cold start — auth interceptor
    // refreshes it on token rotation, but the very first read needs us
    // to copy from storage into the StateProvider.
    if (token != null) {
      _ref.read(currentAccessTokenProvider.notifier).state = token;
    }
    return token != null;
  }

  // ─── Password reset ───────────────────────────────────────────────────────

  /// Re-sends the email-verification link. Server-side rate-limited per
  /// IP + per email + per-email cooldown. Same opaque response for found /
  /// already-verified / not-found (enumeration protection). Per inbox/007.
  Future<void> resendVerification(String email) async {
    await _client.post(
      '/auth/resend-verification',
      data: {'email': email},
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await _client.post(
      ApiConstants.AUTH_FORGOT_PASSWORD,
      data: {'email': email},
    );
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _client.post(
      ApiConstants.AUTH_RESET_PASSWORD,
      // Real contract: {token, password, confirmPassword} — the field is
      // `password`, not `newPassword` (the old name 400'd every reset).
      data: {
        'token': token,
        'password': newPassword,
        'confirmPassword': newPassword,
      },
    );
  }

  // ─── Session management ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.USER_SESSIONS,
    );
    // Sahachiel: `.cast<Map>()` is lazy - it throws later, on iteration, if any
    // element isn't a map. Filter eagerly with whereType so a mixed/garbage
    // sessions list degrades to the valid rows instead of crashing the screen.
    final raw = res.data?['sessions'];
    final sessions = raw is List ? raw : const [];
    return sessions.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> revokeSession(String sessionId) async {
    // Sahachiel: the mobile API deletes sessions through the collection route
    // with a JSON body; there is no `/user/sessions/:id` route server-side.
    await _client.delete(
      ApiConstants.USER_SESSIONS,
      data: {'sessionId': sessionId},
    );
  }

  Future<void> revokeAllOtherSessions() async {
    await _client.delete(
      ApiConstants.USER_SESSIONS,
      data: {'revokeAll': true},
    );
  }
}
