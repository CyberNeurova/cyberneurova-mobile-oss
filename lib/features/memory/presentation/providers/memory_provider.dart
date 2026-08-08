import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/shared/collections/optimistic_revert.dart';
import 'package:cyberneurova_mobile/features/memory/data/models/memory_model.dart';
import 'package:cyberneurova_mobile/features/memory/data/repositories/memory_repository.dart';
import 'package:cyberneurova_mobile/core/agent/neurova_home.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/agent_session_provider.dart';

/// Snapshot of the user's memories — both the list and the aggregate tracker.
/// We hold them together so the screen renders a consistent state and a single
/// refresh updates both.
typedef MemorySnapshot = ({
  List<MemoryModel> memories,
  MemoryTracker? tracker,
  int count,
  int limit
});

final memoryListProvider =
    AsyncNotifierProvider<MemoryListNotifier, MemorySnapshot>(
  MemoryListNotifier.new,
);

class MemoryListNotifier extends AsyncNotifier<MemorySnapshot> {
  @override
  Future<MemorySnapshot> build() async {
    final res = await ref.read(memoryRepositoryProvider).listMemories();
    unawaited(_mirror(res.memories));
    return (
      memories: res.memories,
      tracker: res.tracker,
      count: res.count == 0 ? res.memories.length : res.count,
      limit: res.limit,
    );
  }

  /// Writes what the server holds into `~/.neurova/memory` as markdown.
  ///
  /// The server stays authoritative; this is a mirror, and it says so in its
  /// own INDEX.md. The reason it exists is reach: an agent running ON the phone
  /// can `grep ~/.neurova/memory` without asking our servers what it is
  /// supposed to know about the person in front of it, and the person can read
  /// the same files. A memory you cannot read is one you cannot correct.
  ///
  /// Fire-and-forget: the Memory screen must never wait on a filesystem write,
  /// and a failed mirror is a missing convenience, not a broken feature.
  Future<void> _mirror(List<MemoryModel> memories) async {
    try {
      final home = await ref.read(neurovaHomeProvider.future);
      await MemoryMirror(home).sync([
        for (final m in memories)
          MirroredMemory(
            id: m.id,
            category: m.category,
            importance: m.importance,
            content: m.content,
            createdAt: m.createdAt,
          ),
      ]);
    } catch (_) {
      // No shell home yet (first launch), no space, no permission — all fine.
    }
  }

  Future<void> deleteOne(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final wasAt = positionOf(current.memories, (m) => m.id == id);
    if (wasAt < 0) return;
    final removed = current.memories[wasAt];
    final newMemories = current.memories.where((m) => m.id != id).toList();
    state = AsyncData((
      memories: newMemories,
      tracker: current.tracker,
      count: newMemories.length,
      limit: current.limit,
    ));
    try {
      await ref.read(memoryRepositoryProvider).deleteOne(id);
      // Re-mirror so the file goes too. A mirror that keeps a memory the user
      // just revoked is worse than no mirror — the agent would still read it.
      unawaited(_mirror(newMemories));
    } catch (_) {
      // Put back only this memory. Restoring the whole pre-request snapshot
      // also un-deleted anything else revoked while this call was in flight —
      // and on this screen that means a memory the user believed they had
      // removed is still there, and still being fed to the agent.
      final now = state.valueOrNull;
      if (now != null) {
        final restored = restoreAt(now.memories, removed, wasAt);
        state = AsyncData((
          memories: restored,
          tracker: now.tracker,
          count: restored.length,
          limit: now.limit,
        ));
      }
      rethrow;
    }
  }

  Future<void> clearAll() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData((
      memories: const [],
      tracker: current.tracker,
      count: 0,
      limit: current.limit,
    ));
    try {
      await ref.read(memoryRepositoryProvider).clearAll();
      unawaited(_mirror(const []));
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}
