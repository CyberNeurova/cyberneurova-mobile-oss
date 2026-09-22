import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-message web sources (citation URLs) the server fetched for an answer,
/// so the chat can show a tappable "Sources" chip under the reply instead of
/// dumping URLs into the prose (reference pattern).
///
/// Keyed by message id; stored in SharedPreferences under `sources:<id>` as a
/// JSON string array so the chip survives rebuilds + relaunches. Populated from
/// the run stream's `web_search_results` frame (see chat_provider). Not synced
/// to the server — history messages from before this shipped simply have no
/// entry (their sources, if any, remain in the answer text).
class MessageSources extends Notifier<Map<String, List<String>>> {
  static const _prefix = 'sources:';

  @override
  Map<String, List<String>> build() {
    _hydrate();
    return const {};
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    final loaded = <String, List<String>>{};
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null || raw.isEmpty) continue;
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList();
        if (list.isNotEmpty) loaded[k.substring(_prefix.length)] = list;
      } catch (_) {
        // Ignore a corrupt entry rather than failing the whole hydrate.
      }
    }
    // Merge so any set() that landed during the async hydrate isn't clobbered.
    if (loaded.isNotEmpty) state = {...loaded, ...state};
  }

  List<String> get(String messageId) => state[messageId] ?? const [];

  Future<void> set(String messageId, List<String> sources) async {
    final clean = <String>[
      for (final s in sources)
        if (s.isNotEmpty) s
    ];
    if (clean.isEmpty || messageId.isEmpty) return;
    state = {...state, messageId: clean};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$messageId', jsonEncode(clean));
  }
}

final messageSourcesProvider =
    NotifierProvider<MessageSources, Map<String, List<String>>>(
  MessageSources.new,
);
