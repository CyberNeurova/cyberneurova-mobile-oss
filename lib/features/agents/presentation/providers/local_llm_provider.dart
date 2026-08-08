import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/core/agent/local/local_llm.dart';

const _kLocalBaseUrlKey = 'local_llm_base_url_v1';
const _kLocalModelKey = 'local_llm_model_v1';

/// The local model server the user has chosen, or null.
///
/// Persisted, because a model server on the LAN is a piece of the user's setup
/// rather than a per-session choice — re-entering an IP address on a phone
/// keyboard every launch is how a feature stops getting used.
final localLlmBaseUrlProvider =
    NotifierProvider<LocalLlmBaseUrlNotifier, String?>(
  LocalLlmBaseUrlNotifier.new,
);

class LocalLlmBaseUrlNotifier extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kLocalBaseUrlKey);
  }

  /// Stores [raw] after normalising it. Returns the stored value, or null if
  /// it could not be read as a URL at all.
  Future<String?> set(String raw) async {
    final normalized = LocalLlm.normalizeBaseUrl(raw);
    if (normalized == null) return null;
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalBaseUrlKey, normalized);
    // AFTER the write lands, so the re-read cannot race it.
    ref.invalidate(localRouteResolved);
    return normalized;
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLocalBaseUrlKey);
    ref.invalidate(localRouteResolved);
  }
}

/// Live health of the chosen endpoint.
///
/// Re-probed rather than cached across launches: a model server on someone's
/// laptop is up and down constantly, and a remembered "reachable" would send
/// the user to a dead endpoint and blame the app.
final localLlmStatusProvider = FutureProvider<LocalEndpoint?>((ref) async {
  final base = ref.watch(localLlmBaseUrlProvider);
  if (base == null) return null;
  return LocalLlm.probe(base);
});

/// Loopback servers found by sweeping the usual ports.
///
/// autoDispose: this is a scan the user asked for by opening a screen, not
/// state worth keeping. Leaving it resident would also mean the result goes
/// stale the moment they start or stop a server.
final localLlmDiscoveryProvider =
    FutureProvider.autoDispose<List<LocalEndpoint>>((ref) async {
  return LocalLlm.discoverLocal();
});

/// Which model on the local endpoint to send to, or null to use our server.
///
/// Separate from the endpoint on purpose: having a server configured and
/// actively routing through it are different decisions. Someone can leave a
/// laptop endpoint saved and still use our models on the train, without
/// re-typing an IP when they get home.
final localLlmModelProvider =
    NotifierProvider<LocalLlmModelNotifier, String?>(
  LocalLlmModelNotifier.new,
);

class LocalLlmModelNotifier extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kLocalModelKey);
  }

  Future<void> use(String modelId) async {
    state = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalModelKey, modelId);
    ref.invalidate(localRouteResolved);
  }

  Future<void> stop() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLocalModelKey);
    ref.invalidate(localRouteResolved);
  }
}

/// The endpoint + model to route this turn through, or null for our server.
///
/// One place answers "am I on a local model right now", so the send path has a
/// single branch rather than three conditions that can disagree.
///
/// For the UI only. The send path must use [localRouteResolved] — see there.
final localRouteProvider = Provider<({String baseUrl, String model})?>((ref) {
  final base = ref.watch(localLlmBaseUrlProvider);
  final model = ref.watch(localLlmModelProvider);
  if (base == null || model == null) return null;
  return (baseUrl: base, model: model);
});

/// The same answer, but correct on the first message after a launch.
///
/// Both notifiers above hydrate from SharedPreferences asynchronously: their
/// `build()` returns null and the stored value arrives a moment later. Reading
/// them synchronously — which is what a send does — therefore returns "no local
/// model" for the first turn after every app start, and the message goes to our
/// servers despite the user having chosen otherwise.
///
/// Measured on the SM-A546E, 2026-08-04: with a local model selected and the
/// app restarted, the first reply came back from GLM 5.2.
///
/// Silent wrong-routing is the worst version of this bug — nothing looks
/// broken, the answer is just from somewhere the user did not pick, and on a
/// metered connection they pay for it. So the send path awaits the store
/// instead of trusting whatever happens to be in memory.
/// ## Why it does NOT watch the notifiers
///
/// It used to, so that changing the selection invalidated it. That deadlocked
/// the send path: initialising this provider initialises the notifiers, whose
/// own async `_load()` then lands and invalidates THIS provider — abandoning
/// the future the send was already awaiting. Riverpod says it plainly if you
/// look: "the provider was disposed during loading state, yet no value could
/// be emitted."
///
/// The symptom was a message that sat on "Thinking" forever with no HTTP
/// request ever made and no timeout firing, because nothing downstream of the
/// await ever ran. Reading the store directly and invalidating explicitly on
/// each mutation gives the same freshness with no cycle to deadlock on.
final localRouteResolved =
    FutureProvider<({String baseUrl, String model})?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final base = prefs.getString(_kLocalBaseUrlKey);
  final model = prefs.getString(_kLocalModelKey);
  if (base == null || model == null) return null;
  return (baseUrl: base, model: model);
});
