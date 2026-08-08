import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/shared/collections/optimistic_revert.dart';
import 'package:cyberneurova_mobile/features/prompts/data/models/prompt_model.dart';
import 'package:cyberneurova_mobile/features/prompts/data/repositories/prompt_repository.dart';

final promptsProvider =
    AsyncNotifierProvider<PromptsNotifier, List<PromptModel>>(
  PromptsNotifier.new,
);

class PromptsNotifier extends AsyncNotifier<List<PromptModel>> {
  @override
  Future<List<PromptModel>> build() async {
    return ref.read(promptRepositoryProvider).list();
  }

  Future<void> create({
    required String title,
    required String content,
    String? icon,
  }) async {
    final p = await ref
        .read(promptRepositoryProvider)
        .create(title: title, content: content, icon: icon);
    final current = state.valueOrNull ?? [];
    state = AsyncData([p, ...current]);
  }

  Future<void> edit(
    String id, {
    String? title,
    String? content,
    String? icon,
  }) async {
    final p = await ref
        .read(promptRepositoryProvider)
        .update(id, title: title, content: content, icon: icon);
    final current = state.valueOrNull ?? [];
    state = AsyncData([for (final pr in current) pr.id == id ? p : pr]);
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? [];
    final wasAt = positionOf(current, (p) => p.id == id);
    if (wasAt < 0) return;
    final removed = current[wasAt];
    state = AsyncData(current.where((p) => p.id != id).toList());
    try {
      await ref.read(promptRepositoryProvider).delete(id);
    } catch (_) {
      // Put back only this prompt. Restoring the whole pre-request snapshot also
      // resurrected anything else deleted while this call was in flight.
      state =
          AsyncData(restoreAt(state.valueOrNull ?? current, removed, wasAt));
      rethrow;
    }
  }
}
