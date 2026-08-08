import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/providers/local_llm_provider.dart';

/// The send path awaits this. If it can hang, a message hangs with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves promptly on a cold start with a model stored', () async {
    // The exact state after an app restart: both preferences on disk, both
    // notifiers still holding their null build() value.
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
      'local_llm_model_v1': 'qwen2.5-coder',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Measured on the SM-A546E, 2026-08-04: this future never completed, the
    // send sat on "Thinking" forever, and no HTTP request was ever made — the
    // hang was here, not in the transport.
    final route = await container
        .read(localRouteResolved.future)
        .timeout(const Duration(seconds: 2));

    expect(route, isNotNull);
    expect(route!.baseUrl, 'http://127.0.0.1:8080');
    expect(route.model, 'qwen2.5-coder');
  });

  test('resolves promptly when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final route = await container
        .read(localRouteResolved.future)
        .timeout(const Duration(seconds: 2));

    expect(route, isNull);
  });

  test('an endpoint with no model chosen stays on our server', () async {
    // Having a server configured and routing through it are different
    // decisions — one without the other must not send anywhere.
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container
          .read(localRouteResolved.future)
          .timeout(const Duration(seconds: 2)),
      isNull,
    );
  });

  test('choosing a model takes effect on the next send, not the next launch',
      () async {
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(localRouteResolved.future), isNull);

    await container.read(localLlmModelProvider.notifier).use('llama3.2');

    final route = await container
        .read(localRouteResolved.future)
        .timeout(const Duration(seconds: 2));
    expect(route?.model, 'llama3.2');
  });

  test('turning it off takes effect immediately too', () async {
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
      'local_llm_model_v1': 'llama3.2',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(localRouteResolved.future), isNotNull);

    await container.read(localLlmModelProvider.notifier).stop();

    expect(
      await container
          .read(localRouteResolved.future)
          .timeout(const Duration(seconds: 2)),
      isNull,
    );
  });

  test('forgetting the endpoint also stops routing', () async {
    SharedPreferences.setMockInitialValues({
      'local_llm_base_url_v1': 'http://127.0.0.1:8080',
      'local_llm_model_v1': 'llama3.2',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(localRouteResolved.future), isNotNull);

    await container.read(localLlmBaseUrlProvider.notifier).clear();

    expect(
      await container
          .read(localRouteResolved.future)
          .timeout(const Duration(seconds: 2)),
      isNull,
    );
  });
}
