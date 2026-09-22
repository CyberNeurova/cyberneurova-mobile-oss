import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/user/data/models/usage_model.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(apiClientProvider));
});

class UserRepository {
  UserRepository(this._client);
  final ApiClient _client;

  /// Updates the user's profile fields (name, image, etc.).
  /// Uses the dedicated `/user/profile` PATCH endpoint shipped by the
  /// chat team on 2026-06-01 (see agent_comms inbox/001). The older
  /// `/user/settings` endpoint only accepts preferences (theme, etc.).
  Future<void> updateProfile({String? fullName, String? image}) async {
    await _client.patch(
      ApiConstants.USER_PROFILE,
      data: {
        if (fullName != null) 'fullName': fullName,
        if (image != null) 'image': image,
      },
    );
  }

  /// Permanently deletes the account.
  ///
  /// [password] is OPTIONAL, matching the server contract `{password?,
  /// confirmText:"DELETE MY ACCOUNT"}` — the confirm phrase is the guard, and
  /// the password is verified only when the account has one. A Google or Apple
  /// user never set a password, so requiring it here locked them out of
  /// deleting their own account entirely (Apple 5.1.1(v): deletion must be
  /// available to every account type). Empty is omitted rather than sent as
  /// `""`, so the server sees "no password supplied", not "password is blank".
  Future<void> deleteAccount({String? password}) async {
    await _client.delete(
      ApiConstants.USER_DELETE,
      data: {
        if (password != null && password.isNotEmpty) 'password': password,
        'confirmText': 'DELETE MY ACCOUNT',
      },
    );
  }

  /// One-shot cold-start bundle. Parallel-fetches /auth/me, /user/subscription,
  /// /user/tokens, /user/settings server-side via Promise.allSettled — saves
  /// 4 RTTs on cellular. Includes a `legal.needsReAcceptance` block for the
  /// post-OAuth ToS gate.
  ///
  /// Returns the raw Map so callers can read whichever sections they need
  /// (the legal block, or the user, or settings) without modelling every
  /// section. Sections that errored server-side are `null` in the body.
  Future<Map<String, dynamic>> getBootstrap() async {
    final res = await _client.get<Map<String, dynamic>>('/user/bootstrap');
    return res.data!;
  }

  /// Detailed usage breakdown (session / weekly / weekly-premium / extras).
  /// Per chat-team inbox/007. Legacy v1 accounts get a {legacy: true} flag —
  /// caller falls back to UserModel.tokens for usage display in that case.
  Future<UsageDetail> getUsage() async {
    final res = await _client.get<Map<String, dynamic>>('/user/usage');
    return UsageDetail.fromJson(res.data!);
  }

  /// Updates the user's password. Per chat-team inbox/007: bcrypt-verifies
  /// current pwd, on success revokes all OTHER sessions (current stays).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post(
      '/user/change-password',
      data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  /// Updates the user's email. Requires current password. Verification email
  /// is sent to the NEW address; all OTHER sessions are revoked.
  Future<void> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    await _client.patch(
      '/user/email',
      data: {
        'newEmail': newEmail,
        'currentPassword': currentPassword,
      },
    );
  }

  /// Updates notification preferences.
  Future<void> updateNotifications({
    bool? pushEnabled,
    bool? emailEnabled,
  }) async {
    await _client.patch(
      ApiConstants.USER_SETTINGS,
      data: {
        if (pushEnabled != null) 'pushNotifications': pushEnabled,
        if (emailEnabled != null) 'emailNotifications': emailEnabled,
      },
    );
  }
}
