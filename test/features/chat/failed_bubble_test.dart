import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/message_bubble.dart';

/// A failed turn offers Continue or Retry — never both, and never the wrong one.
///
/// The rule lives in `_FailedBubble`: a run that hit the step limit gets
/// **Continue**, anything else with retry text gets **Retry**. It matters
/// because the two are not interchangeable. Retrying a step-limited run spends
/// the same budget to arrive at the same place and discards what the run
/// already did — files written, packages installed. Continuing keeps it.
///
/// `test/chat/step_limit_test.dart` already pins the failure string and even
/// says "the bubble uses startsWith" — but nothing checked that the bubble
/// actually does. The string and the widget could drift apart silently: change
/// the prefix, and every step-limited run quietly starts offering Retry, which
/// is the expensive wrong answer. This is the half that was missing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // A non-error assistant reply renders the action row, whose reactions
    // notifier awaits SharedPreferences in `build()`. Without a mock the
    // platform channel never answers and the test ends with a pending timer,
    // which reads like a flaky widget test but is really an unstubbed
    // dependency.
    SharedPreferences.setMockInitialValues({});
  });

  Widget host(MessageModel message) => ProviderScope(
        overrides: [
          // An ordinary reply renders `_RichBody`, which asks whether this
          // chat is an agent session; that question is answered from the chat
          // LIST, so drawing one message bubble transitively subscribes to
          // `chatListProvider` and, with nothing stubbed, fires a real HTTP
          // GET. Harmless in the app — the list is already loaded by then —
          // but in a test it is a pending timer and a network call.
          //
          // Answering it directly is also more honest than mocking the
          // transport: these messages are plain chat, not an agent session.
          isAgentSessionProvider('c1').overrideWithValue(false),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, chatId: 'c1'),
          ),
        ),
      );

  MessageModel failed({required String content, String? retryText}) =>
      MessageModel(
        id: 'm1',
        chatId: 'c1',
        role: 'assistant',
        content: content,
        isError: true,
        retryText: retryText,
      );

  testWidgets('a step-limited run offers Continue, not Retry', (tester) async {
    await tester.pumpWidget(host(failed(
      // Real text, prefix included — a run that stops here has done work
      // worth keeping.
      content: '$kStepLimitReason The run is paused.',
      // Retry text is present, so this also proves the step-limit branch
      // WINS over the retry branch rather than merely coming first by luck.
      retryText: 'do the thing',
    )));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('an ordinary failure offers Retry, not Continue', (tester) async {
    await tester.pumpWidget(host(failed(
      content: 'No internet connection.',
      retryText: 'do the thing',
    )));

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('with nothing to retry, neither button is offered',
      (tester) async {
    // Offering Retry with no text to resend produces a button that cannot do
    // anything — worse than no button, because the user spends a tap finding
    // that out.
    await tester.pumpWidget(host(failed(content: 'Something went wrong.')));

    expect(find.text('Retry'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    // The explanation is still shown; only the action is withheld.
    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('the failure message itself is always rendered', (tester) async {
    await tester.pumpWidget(host(failed(
      content: 'No internet connection.',
      retryText: 'x',
    )));

    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets('a non-error message is not a failed bubble', (tester) async {
    // Guards the isError branch itself: if the check were inverted or dropped,
    // every ordinary assistant reply would render as a failure.
    await tester.pumpWidget(host(const MessageModel(
      id: 'm2',
      chatId: 'c1',
      role: 'assistant',
      content: 'Here is your answer.',
    )));

    expect(find.text('Retry'), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });
}
