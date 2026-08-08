import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';

/// Last known chat list, kept on disk so the app opens to something on a bad
/// connection instead of an error page.
///
/// The list is the app's front door. Without this, stepping into a lift turns
/// the whole product into a retry button — the chats exist, we fetched them
/// ten seconds ago, and we still show nothing. Cached titles let someone read
/// what they were working on, and the failure is reported as a stale-data
/// notice rather than an error.
///
/// **Only the first page is kept.** Enough to orient and pick a conversation;
/// paginating a cache would mean reconciling cursors against a list that may
/// have changed server-side, and getting that subtly wrong is worse than
/// showing less.
///
/// Cached per user id: a shared cache would show the previous account's chat
/// titles after a switch, which is a privacy leak, not a stale-data bug.
class ChatListCache {
  const ChatListCache._();

  static const _prefix = 'chat_list_cache_v1_';
  static const _maxChats = 50;

  static String _key(String userId) => '$_prefix$userId';

  /// Overwrites the cached list. Failures are swallowed: a cache that cannot
  /// be written must never take down the request that succeeded.
  static Future<void> save(String userId, List<ChatModel> chats) async {
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final slice = chats.take(_maxChats).map((c) => c.toJson()).toList();
      await prefs.setString(_key(userId), jsonEncode(slice));
    } catch (_) {
      // Best-effort by design.
    }
  }

  /// Returns the cached list, or null when there is nothing usable.
  ///
  /// A decode failure clears the entry rather than throwing: the shape can
  /// change between releases, and a corrupt cache must not make the app
  /// permanently unable to show a list.
  static Future<List<ChatModel>?> load(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>) ChatModel.fromJson(e),
      ];
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key(userId));
      } catch (_) {}
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }
}
