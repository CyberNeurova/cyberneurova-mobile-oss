import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/providers/local_llm_provider.dart';

/// The picker has to report where messages actually go.
///
/// Found the hard way: a local endpoint left selected from testing kept
/// routing every message to localhost while the chip read "Gemma". When that
/// endpoint went away the failure looked like Gemma being broken, which is the
/// worst possible attribution.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('no local model chosen means the server decides', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // The notifiers hydrate asynchronously; pump once so build() has run.
    container.read(localLlmBaseUrlProvider);
    container.read(localLlmModelProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(localRouteProvider), isNull);
  });

  test('a chosen local model takes over the route', () async {
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
      'local_llm_model_v1': 'tinyllama-local',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(localLlmBaseUrlProvider);
    container.read(localLlmModelProvider);
    await Future<void>.delayed(Duration.zero);

    final route = container.read(localRouteProvider);
    expect(route, isNotNull);
    expect(route!.model, 'tinyllama-local');
  });

  test('stopping the local model hands the route back', () async {
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
      'local_llm_model_v1': 'tinyllama-local',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(localLlmBaseUrlProvider);
    container.read(localLlmModelProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(localRouteProvider), isNotNull);

    // What choosing a server model in the picker now does.
    await container.read(localLlmModelProvider.notifier).stop();

    expect(container.read(localRouteProvider), isNull);
    // The endpoint is REMEMBERED — forgetting it because the user picked a
    // server model once would cost them re-typing an IP address.
    expect(container.read(localLlmBaseUrlProvider), 'http://127.0.0.1:8080');
  });
}
