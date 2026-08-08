import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat ids the user archived from the drawer's recents list.
///
/// **Device-local v1.** ChatRepository has no archive endpoint yet — the
/// server only knows create/list/delete — so archived state lives in
/// SharedPreferences and does NOT sync across devices. internal notes asks
/// chat/core for a server-side archived flag; when it lands, this notifier
/// becomes a write-through cache over that field (same migration story as
/// message_reactions_provider.dart, whose persistence pattern this follows).
///
/// Stale ids (chat deleted on another device / via bulk delete) are harmless:
/// the drawer intersects this set with the live chat list, so an id with no
/// matching chat simply never renders. [unarchive] on delete keeps the set
/// tidy anyway.
class ArchivedChats extends Notifier<Set<String>> {
  static const _prefsKey = 'archived_chat_ids_v1';

  @override
  Set<String> build() {
    _hydrate();
    return const {};
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey);
    if (stored != null && stored.isNotEmpty) {
      state = stored.toSet();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.toList());
  }

  bool isArchived(String id) => state.contains(id);

  Future<void> archive(String id) async {
    if (id.isEmpty || state.contains(id)) return;
    state = {...state, id};
    await _persist();
  }

  Future<void> unarchive(String id) async {
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
    await _persist();
  }
}

final archivedChatsProvider = NotifierProvider<ArchivedChats, Set<String>>(
  ArchivedChats.new,
);
