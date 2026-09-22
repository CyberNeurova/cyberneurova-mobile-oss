import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/bot_message_view.dart';

/// A collaboration message is more than text: agents emit `question`,
/// `approval_request`, `task_*`, `file_ref` and `card` blocks. Before this,
/// [BotMessageView]'s predecessor rendered only `text`/`image`, so every one
/// of those blocks came through **blank** — a question with no way to answer,
/// an approval with no buttons. These pin that each typed block renders its
/// content and its controls, and that the answer/approve affordance is gated
/// on a `runId` (you can't answer a run that isn't attached — §5b).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The renderer reads the repository only inside tap handlers, never in
  // build(), so an empty scope is enough to draw every block. (No real
  // ApiClient is constructed unless a button is actually tapped.)
  Widget host(BotMessage m) => ProviderScope(
        child: MaterialApp(home: Scaffold(body: BotMessageView(message: m))),
      );

  BotMessage msg(
    List<Map<String, dynamic>> blocks, {
    String? runId,
    String sender = 'agent',
  }) =>
      BotMessage.tryParse({
        'messageId': 'm1',
        'roomId': 'r1',
        'seq': 1,
        'senderId': 'a1',
        'senderType': sender,
        'blocks': blocks,
        if (runId != null) 'runId': runId,
      })!;

  testWidgets('a question with options renders the prompt + a button each',
      (tester) async {
    await tester.pumpWidget(host(msg([
      {
        'type': 'question',
        'text': 'Which environment?',
        'options': ['staging', 'prod'],
        'runId': 'run1',
      },
    ])));

    expect(find.text('Question'), findsOneWidget);
    expect(find.text('Which environment?'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'staging'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'prod'), findsOneWidget);
  });

  testWidgets('a question with no options offers a free-text answer field',
      (tester) async {
    await tester.pumpWidget(host(msg([
      {'type': 'question', 'text': 'What should I call it?', 'runId': 'run1'},
    ])));

    expect(find.text('What should I call it?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('an approval_request renders summary, risk, Approve + Reject',
      (tester) async {
    await tester.pumpWidget(host(msg([
      {
        'type': 'approval_request',
        'text': 'Send the summary email to the client?',
        'risk': 'high',
        'runId': 'run1',
      },
    ])));

    expect(find.text('Approval needed'), findsOneWidget);
    expect(find.text('Send the summary email to the client?'), findsOneWidget);
    expect(find.text('high'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
  });

  testWidgets('an approval with NO runId anywhere withholds the buttons',
      (tester) async {
    // You cannot approve a run that hasn't attached — offering a button that
    // can only fail is worse than showing the wait state (§5b: answers bind
    // to a runId).
    await tester.pumpWidget(host(msg([
      {'type': 'approval_request', 'text': 'Delete the repository?'},
    ])));

    expect(find.text('Delete the repository?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
    expect(find.textContaining('Waiting for the run'), findsOneWidget);
  });

  testWidgets('an approval falls back to the MESSAGE runId when the block omits it',
      (tester) async {
    // runIdOr(): block-level runId first, else the message's. A block without
    // its own runId is still answerable if the message carries one.
    await tester.pumpWidget(host(msg(
      [
        {'type': 'approval_request', 'text': 'Publish the post?'},
      ],
      runId: 'run-from-message',
    )));

    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    expect(find.textContaining('Waiting for the run'), findsNothing);
  });

  testWidgets('a task_result renders its summary as a card', (tester) async {
    await tester.pumpWidget(host(msg([
      {'type': 'task_result', 'text': 'Wrote report.md (2.1 KB).'},
    ])));

    expect(find.text('Wrote report.md (2.1 KB).'), findsOneWidget);
  });

  testWidgets('a file_ref renders the filename and a human size',
      (tester) async {
    await tester.pumpWidget(host(msg([
      {'type': 'file_ref', 'name': 'report.pdf', 'sizeBytes': 2048},
    ])));

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('a mixed message renders both the text bubble and the card',
      (tester) async {
    await tester.pumpWidget(host(msg([
      {'type': 'text', 'text': 'Heads up:'},
      {
        'type': 'approval_request',
        'text': 'Deploy to production?',
        'runId': 'run1',
      },
    ])));

    expect(find.text('Heads up:'), findsOneWidget);
    expect(find.text('Deploy to production?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
  });

  testWidgets('an unknown block type with text still shows its text',
      (tester) async {
    // Forward-compat: a block kind we don't special-case is treated as text
    // rather than dropped silently.
    await tester.pumpWidget(host(msg([
      {'type': 'some_future_kind', 'text': 'A new kind of block.'},
    ])));

    expect(find.text('A new kind of block.'), findsOneWidget);
  });
}
