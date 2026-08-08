import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/shared/collections/optimistic_revert.dart';
import 'package:cyberneurova_mobile/features/research/data/models/research_models.dart';
import 'package:cyberneurova_mobile/features/research/data/repositories/research_repository.dart';

/// Active category filter — `null` = "All". One of:
/// `cve` / `exploit` / `bugbounty` / `malware` / `pentest`.
final researchCategoryProvider = StateProvider<String?>((_) => null);

/// Paginated list of research sessions, filtered by the active category.
final researchSessionsProvider =
    AsyncNotifierProvider<ResearchSessionsNotifier, List<ResearchSession>>(
  ResearchSessionsNotifier.new,
);

class ResearchSessionsNotifier extends AsyncNotifier<List<ResearchSession>> {
  String? _cursor;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  Future<List<ResearchSession>> build() async {
    final category = ref.watch(researchCategoryProvider);
    _cursor = null;
    _hasMore = true;
    final res =
        await ref.read(researchRepositoryProvider).list(category: category);
    _cursor = res.nextCursor;
    _hasMore = res.hasMore;
    return res.sessions;
  }

  Future<void> loadMore() async {
    // Sahachiel: re-entrancy guard — see ChatListNotifier.loadMore. Prevents
    // duplicate-page fetches + page-skips on a fast scroll.
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final category = ref.read(researchCategoryProvider);
      final res = await ref
          .read(researchRepositoryProvider)
          .list(category: category, cursor: _cursor);
      _cursor = res.nextCursor;
      // See ChatListNotifier._fetch: a `hasMore` with no `nextCursor`
      // cannot be advanced and re-requests page one for ever.
      _hasMore = res.hasMore && res.nextCursor != null;
      // Read the list AFTER the fetch — see ChatListNotifier.loadMore. A
      // snapshot taken before the await reinstates anything deleted or added
      // while the page was in flight.
      final current = state.valueOrNull ?? [];
      // No session twice in the list, and a page that adds nothing new
      // ends the pagination rather than repeating on every scroll.
      final seen = {for (final s in current) s.id};
      final fresh = [
        for (final s in res.sessions)
          if (!seen.contains(s.id)) s
      ];
      if (fresh.isEmpty) {
        _hasMore = false;
        return;
      }
      state = AsyncData([...current, ...fresh]);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? [];
    final wasAt = positionOf(current, (s) => s.id == id);
    if (wasAt < 0) return;
    final removed = current[wasAt];
    state = AsyncData(current.where((s) => s.id != id).toList());
    try {
      await ref.read(researchRepositoryProvider).delete(id);
    } catch (_) {
      // Put back only this session — restoring the whole pre-request snapshot
      // also resurrected anything else deleted while this call was in flight.
      state =
          AsyncData(restoreAt(state.valueOrNull ?? current, removed, wasAt));
      rethrow;
    }
  }
}

/// Full detail for one session (queries + sources). Keyed by session id.
/// autoDispose: opening one session detail shouldn't pin every session
/// detail the user has ever viewed.
final researchDetailProvider =
    FutureProvider.autoDispose.family<ResearchDetail, String>((ref, id) {
  return ref.watch(researchRepositoryProvider).get(id);
});
