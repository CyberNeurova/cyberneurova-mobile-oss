import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/local_llm_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/model_info.dart';

const _kSelectedModelKey = 'selected_model_v1';

/// All available + locked models from `/models`.
final modelsProvider = FutureProvider<ModelsResponse>((ref) async {
  final client = ref.watch(apiClientProvider);
  final res = await client.get<Map<String, dynamic>>(ApiConstants.MODELS);
  return ModelsResponse.fromJson(res.data!);
});

/// The user's currently selected model id. Persisted via SharedPreferences.
/// Falls back to the backend's `defaultModel` if unset.
final selectedModelProvider =
    NotifierProvider<SelectedModelNotifier, String>(SelectedModelNotifier.new);

class SelectedModelNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'tiny-neurova';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kSelectedModelKey);
    if (saved != null) state = saved;
  }

  Future<void> select(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedModelKey, id);
  }
}

/// The capability set for the model the user will actually send on
/// (i.e. matches [effectiveModelProvider], not [selectedModelProvider]
/// — free users get `tiny-neurova` regardless of saved selection).
///
/// Returns `null` while `/models` is still loading OR when the server
/// hasn't shipped per-model capabilities yet (older backend), in which
/// case the UI should fall back to its old "show everything, react to
/// 403" behaviour. Anything that pre-gates UI should null-coalesce.
final effectiveModelInfoProvider = Provider<ModelInfo?>((ref) {
  final id = ref.watch(effectiveModelProvider);
  final modelsAsync = ref.watch(modelsProvider);
  final models = modelsAsync.valueOrNull;
  if (models == null) return null;
  for (final m in models.models) {
    if (m.id == id) return m;
  }
  for (final m in models.locked) {
    if (m.id == id) return m;
  }
  return null;
});

/// The model id we'll ACTUALLY send on the wire. Policy:
///   - Free tier → always `tiny-neurova` (the only free model).
///   - Paid tier → user's persisted selection, BUT if that selection is in
///     the locked list (e.g., they downgraded), fall back to the backend's
///     `defaultModel`. Don't overwrite the saved preference — the user may
///     upgrade again.
/// Reads modelsProvider non-blockingly: if not loaded yet, trusts the
/// saved selection (the server will still reject MODEL_ACCESS_DENIED
/// loud enough for us to surface a snackbar).
final effectiveModelProvider = Provider<String>((ref) {
  final selected = ref.watch(selectedModelProvider);
  final user = ref.watch(authProvider).valueOrNull;

  if (user == null || user.tier == 'free') return 'tiny-neurova';

  final modelsAsync = ref.watch(modelsProvider);
  final models = modelsAsync.valueOrNull;
  if (models == null) return selected;

  final isLocked = models.locked.any((m) => m.id == selected);
  if (isLocked) return models.defaultModel;
  return selected;
});

/// Why the model actually in use is not the one the user picked.
///
/// The substitution above is reasonable policy. Doing it silently is not: the
/// owner watched the chip go from Gemma to Tiny Neurova with no notice, and
/// the first thing they noticed was tool calls quietly stopping. A model the
/// user did not choose, presented as though they had, is indistinguishable
/// from the agent getting worse — and it sends them looking for a bug in the
/// agent instead of at their plan.
enum ModelSubstitution {
  /// Sending exactly what was picked.
  none,

  /// Signed out, or on the free tier, which has one model.
  freeTier,

  /// The pick is real but not available on this plan — usually a downgrade.
  /// The saved preference is deliberately left alone in case they upgrade.
  lockedForTier,

  /// A local model is answering, so nothing server-side applies.
  localRoute,
}

final modelSubstitutionProvider = Provider<ModelSubstitution>((ref) {
  if (ref.watch(localRouteProvider) != null) {
    return ModelSubstitution.localRoute;
  }
  final selected = ref.watch(selectedModelProvider);
  final effective = ref.watch(effectiveModelProvider);
  if (selected == effective) return ModelSubstitution.none;

  final user = ref.watch(authProvider).valueOrNull;
  if (user == null || user.tier == 'free') return ModelSubstitution.freeTier;
  return ModelSubstitution.lockedForTier;
});

/// One line the user can act on, or null when nothing was substituted.
String? modelSubstitutionReason(ModelSubstitution s) => switch (s) {
      ModelSubstitution.none || ModelSubstitution.localRoute => null,
      ModelSubstitution.freeTier =>
        'The free plan has one model, so that is what answers — whatever is '
            'picked here.',
      ModelSubstitution.lockedForTier =>
        'Your plan does not include the model you picked, so an included one '
            'is answering instead. Your choice is kept in case you upgrade.',
    };
