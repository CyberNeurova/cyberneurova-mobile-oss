import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/line_diff.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/agent_tool_card.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/diff_body.dart';

void main() {
  group('DiffStat', () {
    test('counts changed lines and ignores the file headers', () {
      const diff = '--- a/notes.md\n'
          '+++ b/notes.md\n'
          '@@ -1,3 +1,4 @@\n'
          ' unchanged\n'
          '-gone\n'
          '+added\n'
          '+also added\n';
      final stat = DiffStat.parse(diff);
      // +++/--- are the headers, not changes. Counting them would report
      // every single-line edit as one line bigger than it is.
      expect(stat.added, 2);
      expect(stat.removed, 1);
      expect(stat.isEmpty, isFalse);
    });

    test('an unchanged write reports nothing rather than zeros', () {
      expect(const DiffStat(added: 0, removed: 0).isEmpty, isTrue);
      expect(DiffStat.parse('').isEmpty, isTrue);
    });

    test('agrees with the diff the write tool actually produces', () {
      // The real path: FileWriteTool emits unifiedDiff(), the card parses it.
      // If those two ever disagree the badge silently lies about the edit.
      final diff = unifiedDiff('a\nb\nc\n', 'a\nB\nc\nd\n');
      final stat = DiffStat.parse(diff);
      expect(stat.added, 2, reason: 'B and d');
      expect(stat.removed, 1, reason: 'b');
    });
  });

  group('AgentToolCard', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    ToolCardItem card({required String output}) => ToolCardItem(
          callId: 'c1',
          tool: 'file_write',
          input: const {'path': 'notes.md'},
          state: ToolCardState.succeeded,
        )
          ..output = output
          ..summary = 'Wrote notes.md';

    testWidgets('a file edit shows how big the change was without expanding',
        (tester) async {
      final diff = unifiedDiff('a\nb\n', 'a\nB\nc\n');
      await tester.pumpWidget(wrap(AgentToolCard(card: card(output: diff))));

      expect(find.text('+2'), findsOneWidget);
      expect(find.text('−1'), findsOneWidget);
    });

    testWidgets('ordinary output gets no diff badge', (tester) async {
      await tester.pumpWidget(wrap(AgentToolCard(
        card: card(output: 'total 4\ndrwxr-xr-x  2 root root'),
      )));

      // A listing that happens to contain a dash must not be read as a diff.
      expect(find.byType(DiffStatChip), findsNothing);
    });

    testWidgets('expanding an edit labels it CHANGES and colours it',
        (tester) async {
      final diff = unifiedDiff('a\nb\n', 'a\nB\n');
      await tester.pumpWidget(wrap(AgentToolCard(card: card(output: diff))));

      expect(find.text('CHANGES'), findsNothing, reason: 'collapsed by default');

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      expect(find.text('CHANGES'), findsOneWidget);
      expect(find.byType(DiffBody), findsOneWidget);
    });

    testWidgets('expanding plain output labels it OUTPUT', (tester) async {
      await tester.pumpWidget(wrap(AgentToolCard(card: card(output: 'hello'))));
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      expect(find.text('OUTPUT'), findsOneWidget);
      expect(find.byType(DiffBody), findsNothing);
    });
  });
}
