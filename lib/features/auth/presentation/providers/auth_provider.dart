import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/auth/data/user_cache.dart';
import 'package:cyberneurova_mobile/core/constants/dev_flags.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/user_model.dart';
import 'package:cyberneurova_mobile/features/auth/data/repositories/auth_repository.dart';

// Current authenticated user; null = logged out
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

/// Set when the session was lost involuntarily (refresh-token revoked or
/// expired → transparent refresh failed → forced logout). The login screen
/// reads this to explain WHY the user is suddenly looking at it, then clears
/// it. Without this the bounce reads as a random crash-to-login.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);

/// Tier for the dev-bypass sandbox user. Defaults to 'pro' so every gated
/// surface is reachable; run with `--dart-define=DEV_AUTH_BYPASS_TIER=free`
/// to preview the free-state UI (Upgrade pills, locked models, paywall
/// sheets). Same kDebugMode double-gate as [devAuthBypass] — the define is
/// inert in release builds because _devUser is never returned there.
const _devTier =
    String.fromEnvironment('DEV_AUTH_BYPASS_TIER', defaultValue: 'pro');

const _devUser = UserModel(
  id: 'dev-bypass-user',
  email: 'dev@cyberneurova.local',
  name: 'Dev Bypass',
  emailVerified: true,
  tier: _devTier,
  subscription: SubscriptionModel(tier: _devTier),
  tokens: TokensModel(used: 12000, limit: 1000000, remaining: 988000),
);

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    if (devAuthBypass) return _devUser;
    // Sahachiel: the AuthInterceptor clears the token mirror
    // (currentAccessTokenProvider -> null) when a transparent refresh fails
    // (revoked/expired refresh token). It never touches authProvider, so the
    // router's redirect kept the user on an authed screen where every request
    // 401s. Reflect the lost session as a logout so _AuthListenable fires and
    // bounces them to /auth/login.
    ref.listen<String?>(currentAccessTokenProvider, (prev, next) {
      if (next == null && prev != null && state.valueOrNull != null) {
        ref.read(sessionExpiredProvider.notifier).state = true;
        state = const AsyncData(null);
      }
    });
    final repo = ref.watch(authRepositoryProvider);
    if (await repo.hasSession()) {
      try {
        final user = await repo.getMe();
        unawaited(UserCache.save(user));
        return user;
      } on UnauthorizedException {
        // The session is genuinely gone. Log out.
        await UserCache.clear();
        return null;
      } on ForbiddenException {
        await UserCache.clear();
        return null;
      } catch (_) {
        // Anything else — no network, timeout, DNS, a 500 — is NOT a logout.
        //
        // This used to `return null` for every failure, so opening the app in
        // a lift showed "Sign in to start chatting" with the chat list gone.
        // The session was still perfectly valid; we simply could not refresh
        // the profile. Telling someone they are signed out when they are not
        // invites them to re-authenticate for no reason, and looks like data
        // loss.
        //
        // We hold a valid token, so stay signed in on the last known profile.
        // If the token really is dead, the first authed request 401s and the
        // interceptor above clears the session properly.
        return await UserCache.load();
      }
    }
    await UserCache.clear();
    return null;
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final tokens = await repo.login(email: email, password: password);
      // The login response includes basic user info, but /auth/me has the
      // canonical state with subscription + tokens — fetch it for consistency.
      // Sahachiel: use the same retry + JWT-skeleton fallback as the OAuth
      // paths. /auth/me is flaky right after a freshly minted JWT; without the
      // fallback a transient failure throws and logs the user back out even
      // though valid tokens were already persisted by repo.login().
      return tokens.user ?? await _fetchMeWithFallback(repo, tokens.accessToken);
    });
  }

  /// Registers a new account. The server requires email verification before
  /// login is allowed — does NOT auto-log-in. The UI should redirect the user
  /// to a "check your email" screen on success.
  ///
  /// Returns the [RegisterResponse] so the caller can react to
  /// [emailVerificationRequired]. Throws on failure.
  Future<RegisterResponse> register({
    required String email,
    required String password,
    required String tosVersion,
    String? fullName,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    return repo.register(
      email: email,
      password: password,
      tosVersion: tosVersion,
      fullName: fullName,
    );
  }

  Future<void> loginWithGoogle(String idToken) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final tokens = await repo.loginWithGoogle(idToken);
      return tokens.user ?? await _fetchMeWithFallback(repo, tokens.accessToken);
    });
  }

  Future<void> loginWithApple({
    required String idToken,
    String? nonce,
    String? email,
    String? firstName,
    String? lastName,
    String? authorizationCode,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final tokens = await repo.loginWithApple(
        idToken: idToken,
        nonce: nonce,
        email: email,
        firstName: firstName,
        lastName: lastName,
        authorizationCode: authorizationCode,
      );
      return tokens.user ?? await _fetchMeWithFallback(repo, tokens.accessToken);
    });
  }

  /// /auth/me right after a fresh OAuth sign-in occasionally fails — looks
  /// like server-side token propagation/cache warming after a brand-new JWT
  /// is minted. The reproduced UX was: tap Google/Apple → "access denied"
  /// snackbar, but on app relaunch the same stored tokens worked fine
  /// (build() runs getMe on relaunch and it succeeds).
  ///
  /// Strategy:
  /// 1. Retry getMe up to 5x with exponential backoff (total ~3.1s).
  /// 2. If still failing AND we have a valid access token, decode the JWT
  ///    payload for a skeleton user (id + email at minimum) so the user
  ///    gets into the app. The router treats AsyncData(null) as
  ///    logged-out, which is the wrong call here — OAuth actually succeeded.
  /// 3. A background refresh attempts to fill in the full profile after
  ///    a 4s delay; if it succeeds, the UI updates seamlessly.
  Future<UserModel?> _fetchMeWithFallback(
    AuthRepository repo,
    String accessToken,
  ) async {
    Object? lastError;
    const delaysMs = [0, 200, 400, 800, 1600]; // total ~3.0s
    for (final delay in delaysMs) {
      if (delay > 0) await Future.delayed(Duration(milliseconds: delay));
      try {
        return await repo.getMe();
      } catch (e) {
        lastError = e;
      }
    }
    // All retries exhausted. Decode the JWT for a skeleton user instead
    // of throwing — OAuth itself succeeded, the user IS authenticated,
    // we just can't read their profile yet. Schedule a background refresh.
    final skeleton = _skeletonFromJwt(accessToken);
    if (skeleton != null) {
      Future.delayed(const Duration(seconds: 4), () async {
        try {
          state = AsyncData(await repo.getMe());
        } catch (_) {
          // Next user-driven refresh (open a chat, hit settings) will retry.
        }
      });
      return skeleton;
    }
    throw lastError ?? Exception('getMe failed and JWT was unreadable');
  }

  /// Build a minimal [UserModel] from a JWT's payload. JWTs are three
  /// base64url-encoded segments separated by `.`; the middle segment is
  /// JSON. We only need `sub`/`userId` + `email` to construct a usable
  /// skeleton — the rest defaults to "free tier, no subscription" until
  /// the next /auth/me succeeds.
  ///
  /// Returns null if the token isn't a parseable JWT.
  UserModel? _skeletonFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      // Base64url → base64 + padding to multiple of 4.
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final json = jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;
      final id = (json['sub'] ?? json['userId'] ?? json['id']) as String?;
      final email = json['email'] as String?;
      if (id == null || email == null) return null;
      return UserModel(
        id: id,
        email: email,
        name: json['name'] as String?,
        tier: (json['tier'] as String?) ?? 'free',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshMe() async {
    final repo = ref.read(authRepositoryProvider);
    state = AsyncData(await repo.getMe());
  }

  Future<void> logout() async {
    // Null the auth state BEFORE the repo clears the token mirror — otherwise
    // the mirror listener in build() reads the clear as an involuntary
    // session loss and raises sessionExpiredProvider.
    state = const AsyncData(null);
    // The cached profile must not outlive the session — leaving it would show
    // the previous account's name and tier on the sign-in screen.
    await UserCache.clear();
    await ref.read(authRepositoryProvider).logout();
  }
}
