import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/shared/collections/optimistic_revert.dart';
import 'package:cyberneurova_mobile/features/projects/data/models/project_model.dart';
import 'package:cyberneurova_mobile/features/projects/data/repositories/project_repository.dart';

final projectsProvider =
    AsyncNotifierProvider<ProjectsNotifier, List<ProjectModel>>(
  ProjectsNotifier.new,
);

class ProjectsNotifier extends AsyncNotifier<List<ProjectModel>> {
  @override
  Future<List<ProjectModel>> build() async {
    return ref.read(projectRepositoryProvider).list();
  }

  Future<ProjectModel> create({
    required String name,
    String? description,
    String? icon,
    String? color,
  }) async {
    final p = await ref.read(projectRepositoryProvider).create(
          name: name,
          description: description,
          icon: icon,
          color: color,
        );
    final current = state.valueOrNull ?? [];
    state = AsyncData([p, ...current]);
    return p;
  }

  Future<void> edit(
    String id, {
    String? name,
    String? description,
    String? icon,
    String? color,
  }) async {
    final p = await ref.read(projectRepositoryProvider).update(
          id,
          name: name,
          description: description,
          icon: icon,
          color: color,
        );
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
      await ref.read(projectRepositoryProvider).delete(id);
    } catch (_) {
      // Put back only this project. Restoring the whole pre-request snapshot also
      // resurrected anything else deleted while this call was in flight.
      state =
          AsyncData(restoreAt(state.valueOrNull ?? current, removed, wasAt));
      rethrow;
    }
  }
}
