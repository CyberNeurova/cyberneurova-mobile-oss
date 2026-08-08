import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-message thumbs-up / thumbs-down reactions, persisted locally.
///
/// Keyed by message id. Values: -1 (down), 0 (none / cleared), +1 (up).
/// Stored in SharedPreferences under `reaction:<id>` so the user's choice
/// survives rebuilds + app relaunches.
///
/// **Not** synced to the server yet — the backend `/analytics/events` is
/// queued (#49). When it lands, hook `set()` to POST the rating server-side
/// in addition to writing the local prefs entry.
class MessageReactions extends Notifier<Map<String, int>> {
  static const _prefix = 'reaction:';

  @override
  Map<String, int> build() {
    _hydrate();
    return const {};
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    final loaded = <String, int>{};
    for (final k in keys) {
      final v = prefs.getInt(k);
      if (v != null && v != 0) {
        loaded[k.substring(_prefix.length)] = v;
      }
    }
    state = loaded;
  }

  int get(String messageId) => state[messageId] ?? 0;

  Future<void> set(String messageId, int value) async {
    final clamped = value.clamp(-1, 1);
    state = {...state, messageId: clamped};
    final prefs = await SharedPreferences.getInstance();
    if (clamped == 0) {
      await prefs.remove('$_prefix$messageId');
    } else {
      await prefs.setInt('$_prefix$messageId', clamped);
    }
  }
}

final messageReactionsProvider =
    NotifierProvider<MessageReactions, Map<String, int>>(
  MessageReactions.new,
);
