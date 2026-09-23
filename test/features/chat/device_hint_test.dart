import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/model_info.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/model_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_composer.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/device_suggestion_chip.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';

/// The condition, not the classifier.
///
/// Driving this on the device cost three build cycles and proved nothing: the
/// chat I kept landing in was a Console session, where the hint is suppressed
/// on purpose, so "no chip" was correct behaviour that looked exactly like a
/// bug. Overriding the surface is the only way to see both branches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chatId = 'test-chat';

  Widget host({
    required AgentSurface? surface,
    required TextEditingController controller,
  }) {
    return ProviderScope(
      overrides: [
        agentSurfaceProvider(chatId).overrideWithValue(surface),
        // The composer reaches for the model list to render its picker; in a
        // test there is no API client behind it.
        modelsProvider.overrideWith((ref) async => const ModelsResponse(
              models: [
                ModelInfo(id: 'cyberneurova-gemma', name: 'CyberNeurova Gemma')
              ],
            )),
      ],
      child: MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: ChatComposer(
            chatId: chatId,
            controller: controller,
            sending: false,
            onSend: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('a plain chat offers Console for a device request',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(surface: null, controller: controller));
    await tester.pump();

    expect(find.byType(DeviceSuggestionChip), findsNothing,
        reason: 'nothing typed yet');

    controller.text = 'list my files';
    await tester.pump();

    expect(find.byType(DeviceSuggestionChip), findsOneWidget);
    // The reason is the useful part, not the suggestion.
    expect(find.textContaining('cannot run anything on your phone'),
        findsOneWidget);
  });

  testWidgets('ordinary conversation is left alone', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(surface: null, controller: controller));

    controller.text = 'how do i install ripgrep on debian';
    await tester.pump();

    expect(find.byType(DeviceSuggestionChip), findsNothing);
  });

  testWidgets('a Console session never offers to open Console',
      (tester) async {
    // The case that made this look broken on device for three builds.
    final controller = TextEditingController();
    await tester.pumpWidget(
        host(surface: AgentSurface.console, controller: controller));

    controller.text = 'list my files';
    await tester.pump();

    expect(find.byType(DeviceSuggestionChip), findsNothing);
  });

  testWidgets('dismissing it keeps it dismissed for the conversation',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(surface: null, controller: controller));

    controller.text = 'list my files';
    await tester.pump();
    expect(find.byType(DeviceSuggestionChip), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.byType(DeviceSuggestionChip), findsNothing);

    // Someone who has said "no, I meant here" should not be asked again.
    controller.text = 'run the tests on my phone';
    await tester.pump();
    expect(find.byType(DeviceSuggestionChip), findsNothing);
  });
}
