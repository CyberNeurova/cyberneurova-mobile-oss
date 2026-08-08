import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/auth/data/models/user_model.dart';

/// The last profile the server confirmed.
///
/// Exists so that losing the network does not look like losing the account.
/// `getMe()` failing used to mean "signed out", which on a bad connection
/// showed a sign-in screen and an empty chat list to someone holding a
/// perfectly valid token.
///
/// This is a **display** fallback, never an authorisation decision: it is only
/// consulted when a session already exists, and any 401/403 clears it. A
/// cached profile can never keep someone signed in whose token is actually
/// dead — the first authed request settles that.
class UserCache {
  const UserCache._();

  static const _key = 'auth_user_cache_v1';

  static Future<void> save(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(user.toJson()));
    } catch (_) {
      // Best-effort; a cache write must never fail a successful login.
    }
  }

  static Future<UserModel?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return UserModel.fromJson(decoded);
    } catch (_) {
      await clear();
      return null;
    }
  }

  /// Called on real sign-out and on 401/403 — the cache must never outlive the
  /// session it describes.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
