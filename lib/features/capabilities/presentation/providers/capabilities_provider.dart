import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/features/capabilities/data/models/capability_models.dart';
import 'package:cyberneurova_mobile/features/capabilities/data/repositories/capabilities_repository.dart';

/// What [id] was set to before an optimistic flip, or null if it is not in
/// the list.
bool? _enabledOf(List<CapabilityModel> list, String id) {
  for (final c in list) {
    if (c.id == id) return c.enabled;
  }
  return null;
}

/// Undo one optimistic flip, leaving every other row alone.
///
/// The revert used to restore the whole pre-flight snapshot. Toggling is one
/// request per row and the screen lets you flip several in a row, so a failure
/// arriving late wiped out every other toggle made while it was in flight —
/// and those had already succeeded server-side. The switches would spring back
/// to a state the server did not agree with, silently, until a refresh.
///
/// Reverting to the REMEMBERED value rather than `!enabled` matters for the
/// same reason: by the time the failure lands, the row may have been toggled
/// again, and inverting whatever is on screen is not the same as putting back
/// what was there.
List<CapabilityModel> _revert(
  List<CapabilityModel> list,
  String id,
  bool? was,
) {
  if (was == null) return list;
  return [
    for (final c in list)
      if (c.id == id) c.copyWith(enabled: was) else c,
  ];
}

// ─── Skills ──────────────────────────────────────────────────────────────────

final skillsProvider =
    AsyncNotifierProvider<SkillsNotifier, List<CapabilityModel>>(
  SkillsNotifier.new,
);

class SkillsNotifier extends AsyncNotifier<List<CapabilityModel>> {
  @override
  Future<List<CapabilityModel>> build() async {
    final res = await ref.read(capabilitiesRepositoryProvider).listSkills();
    return res.items;
  }

  Future<void> toggle(String id, bool enabled) async {
    final current = state.valueOrNull ?? [];
    final was = _enabledOf(current, id);
    // Optimistic flip
    state = AsyncData([
      for (final s in current)
        if (s.id == id) s.copyWith(enabled: enabled) else s,
    ]);
    try {
      await ref.read(capabilitiesRepositoryProvider).toggleSkill(id, enabled);
    } catch (_) {
      state = AsyncData(_revert(state.valueOrNull ?? current, id, was));
      rethrow;
    }
  }
}

// ─── Tools ───────────────────────────────────────────────────────────────────

final toolsProvider =
    AsyncNotifierProvider<ToolsNotifier, List<CapabilityModel>>(
  ToolsNotifier.new,
);

class ToolsNotifier extends AsyncNotifier<List<CapabilityModel>> {
  @override
  Future<List<CapabilityModel>> build() async {
    final res = await ref.read(capabilitiesRepositoryProvider).listTools();
    return res.items;
  }

  Future<void> toggle(String id, bool enabled) async {
    final current = state.valueOrNull ?? [];
    final was = _enabledOf(current, id);
    state = AsyncData([
      for (final t in current)
        if (t.id == id) t.copyWith(enabled: enabled) else t,
    ]);
    try {
      await ref.read(capabilitiesRepositoryProvider).toggleTool(id, enabled);
    } catch (_) {
      state = AsyncData(_revert(state.valueOrNull ?? current, id, was));
      rethrow;
    }
  }
}
