import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/code_panel.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/message_bubble.dart';

/// Where a fenced code block stops being inline text and becomes a card.
///
/// The rule is six lines: shorter snippets stay in the markdown so a two-line
/// command reads as part of the sentence, longer ones get the teaser with
/// copy, expand and "Show all".
///
/// It fired a line early on every block. The fence regex captures everything
/// up to the closing ```, which includes the newline that ends the last line
/// of code — so `a\nb\n` counted as three lines, not two, and a five-line
/// snippet crossed a six-line threshold. That newline is markdown syntax, not
/// content.
///
/// Testing this through the widget rather than the (private) segmenter is the
/// point: the threshold only matters because of what it renders.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> show(WidgetTester tester, String content) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [isAgentSessionProvider('c1').overrideWithValue(false)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: MessageModel(
                id: 'm1',
                chatId: 'c1',
                role: 'assistant',
                content: content,
              ),
              chatId: 'c1',
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// A fence exactly as a model writes one — newline before the closing ```.
  String fence(int lines, {String lang = 'py'}) {
    final body = [for (var i = 1; i <= lines; i++) 'line$i'].join('\n');
    return '```$lang\n$body\n```';
  }

  testWidgets('a five-line block stays inline', (tester) async {
    // The case the off-by-one broke: five lines counted as six and became a
    // card, so short snippets stopped reading as part of the reply.
    await show(tester, fence(5));
    expect(find.byType(CodeTeaser), findsNothing);
  });

  testWidgets('a six-line block becomes a card', (tester) async {
    await show(tester, fence(6));
    expect(find.byType(CodeTeaser), findsOneWidget);
  });

  testWidgets('a two-line command is never a card', (tester) async {
    await show(tester, '```bash\ncd /tmp\nls -la\n```');
    expect(find.byType(CodeTeaser), findsNothing);
  });

  testWidgets('a named file is a card at any length', (tester) async {
    // Deliberate: the model naming the file is the signal that the block is
    // meant to become one, and a four-line config would otherwise be denied
    // the only action that matters.
    await show(tester, '```python title=setup.py\nx = 1\n```');
    expect(find.byType(CodeTeaser), findsOneWidget);
  });

  testWidgets('mermaid is a card at any length', (tester) async {
    await show(tester, '```mermaid\ngraph TD;\nA-->B;\n```');
    expect(find.byType(CodeTeaser), findsOneWidget);
  });
}
