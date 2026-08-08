import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/message_bubble.dart';

/// The action row under an assistant reply, and the two things it must not do.
///
/// **Regenerate belongs to the latest turn only.** Its handler walks backwards
/// to the most recent user message in the whole chat and resends that — which
/// is correct precisely because the button is confined to the last reply. Show
/// it on an older bubble and it stops meaning "try that again": it resends the
/// newest question and overwrites a reply the user had already read and moved
/// past. The guard is one bool, `showRetry: isLatest`, and nothing checked it.
///
/// **Continue must vanish while a stream is running.** It resumes a truncated
/// turn, so two taps queue two resumes into the same message. The `!streaming`
/// half of that condition is the entire defence and is invisible on screen —
/// the pill simply isn't there — which is exactly the kind of thing that gets
/// "simplified" away.
class _Truncated extends TruncatedMessagesNotifier {
  _Truncated(this._ids);
  final Set<String> _ids;

  @override
  Set<String> build() => _ids;
}

/// Pump, then let the entrance animation finish.
///
/// The latest bubble fades and slides in over 200ms (flutter_animate).
/// Ending a test mid-animation surfaces as "a Timer is still pending",
/// which reads like widget flakiness but is just an unfinished tween —
/// every failure here was an `isLatest: true` case and nothing else.
Future<void> _pump(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(
    MessageModel message, {
    bool isLatest = false,
    Set<String> truncated = const {},
    bool streaming = false,
  }) =>
      ProviderScope(
        overrides: [
          // Drawing a bubble otherwise asks whether this chat is an agent
          // session, which is answered from the chat list and fires a live
          // HTTP GET. These are plain chat messages.
          isAgentSessionProvider('c1').overrideWithValue(false),
          truncatedMessagesProvider.overrideWith(() => _Truncated(truncated)),
          streamRunningProvider.overrideWith((ref) => streaming),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              chatId: 'c1',
              isLatest: isLatest,
            ),
          ),
        ),
      );

  const reply = MessageModel(
    id: 'm1',
    chatId: 'c1',
    role: 'assistant',
    content: 'Here is your answer.',
  );

  group('Regenerate', () {
    testWidgets('is offered on the latest assistant turn', (tester) async {
      await _pump(tester, host(reply, isLatest: true));
      expect(find.byTooltip('Regenerate'), findsOneWidget);
    });

    testWidgets('is withheld from every earlier turn', (tester) async {
      // The history-rewriting case. Regenerate resends the chat's most recent
      // user message, so on an old bubble it would answer a question the user
      // asked much later and replace a reply they had already accepted.
      await _pump(tester, host(reply, isLatest: false));
      expect(find.byTooltip('Regenerate'), findsNothing);
    });

    testWidgets('a user message never carries the action row', (tester) async {
      // The row is assistant-only; offering Copy and thumbs on the user's own
      // words is noise, and Regenerate there has no meaning at all.
      await _pump(
          tester,
          host(
            const MessageModel(
              id: 'u1',
              chatId: 'c1',
              role: 'user',
              content: 'my question',
            ),
            isLatest: true,
          ));
      expect(find.byTooltip('Regenerate'), findsNothing);
      expect(find.byTooltip('Copy'), findsNothing);
    });
  });

  group('Continue', () {
    testWidgets('appears for a turn the server marked truncated',
        (tester) async {
      await _pump(tester, host(reply, truncated: {'m1'}));
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('is absent for a turn that finished normally', (tester) async {
      // Driven by the server's done.truncated flag, not a fence heuristic —
      // a reply ending mid-code-block is not automatically incomplete.
      await _pump(tester, host(reply));
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('disappears while a stream is in flight', (tester) async {
      // Two taps would queue two resumes into the same message. The message
      // is still marked truncated here — only the streaming flag differs, so
      // this isolates the half of the condition that does the protecting.
      await _pump(
        tester,
        host(reply, truncated: {'m1'}, streaming: true),
      );
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('is independent of Regenerate', (tester) async {
      // Both can be on the same bubble: the latest turn, truncated, idle.
      await _pump(
        tester,
        host(reply, isLatest: true, truncated: {'m1'}),
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.byTooltip('Regenerate'), findsOneWidget);
    });
  });

  testWidgets('an empty assistant message gets no action row', (tester) async {
    // Nothing to copy, speak, rate or regenerate — a row of dead buttons
    // under a blank bubble.
    await _pump(
        tester,
        host(
          const MessageModel(
            id: 'm3',
            chatId: 'c1',
            role: 'assistant',
            content: '',
          ),
          isLatest: true,
        ));
    expect(find.byTooltip('Copy'), findsNothing);
    expect(find.byTooltip('Regenerate'), findsNothing);
  });
}
