import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/bots/data/bot_turn_runner.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';

/// The executor's pure logic: what the model actually sees for a turn, and the
/// presence decision that gates whether mobile runs at all.
///
/// The prompt is where a group turn lives or dies: an agent's reply is a
/// `task_result` block (the message is authored by the human device — §2), so
/// if the transcript were built off `senderType` or only `text` blocks, group
/// members would never see each other and every agent would answer the human
/// in a vacuum. `botTurnLine` is the fix; these pin it.
void main() {
  BotMessage msg(List<Map<String, dynamic>> blocks) => BotMessage.tryParse({
        'messageId': 'm',
        'roomId': 'r',
        'seq': 1,
        'senderId': 'u1',
        'senderType': 'human',
        'blocks': blocks,
      })!;

  group('botTurnLine', () {
    test('a human text message is attributed to User', () {
      expect(botTurnLine(msg([
            {'type': 'text', 'text': 'hello team'}
          ])),
          'User: hello team');
    });

    test('an agent task_result is attributed to its authorName', () {
      expect(
          botTurnLine(msg([
            {'type': 'task_result', 'text': 'built the parser', 'authorName': 'Coder'}
          ])),
          'Coder: built the parser');
    });

    test('a task_started (thinking) block is not transcript', () {
      // The "On it — thinking…" placeholder must never become a turn the next
      // agent reasons about.
      expect(
          botTurnLine(msg([
            {'type': 'task_started', 'text': 'On it — thinking…'}
          ])),
          isNull);
    });

    test('an image-only message has no transcript line', () {
      expect(
          botTurnLine(msg([
            {'type': 'image', 'url': '/api/core/files/x'}
          ])),
          isNull);
    });
  });

  group('composeBotTurnPrompt', () {
    final agent = BotAgent.tryParse({
      'agentId': 'a1',
      'name': 'Coder',
      'description': 'Writes and runs code.',
      'model': 'cyberneurova-qwen3.8',
    })!;

    test('carries persona, transcript, the new turn, and a reply cue', () {
      final history = [
        msg([
          {'type': 'text', 'text': 'hi team'}
        ]),
        msg([
          {'type': 'task_result', 'text': 'I mapped the schema', 'authorName': 'Researcher'}
        ]),
      ];
      final p = composeBotTurnPrompt(agent, history, 'what next?');

      expect(p, contains('You are Coder'));
      expect(p, contains('Writes and runs code.'));
      expect(p, contains('Conversation so far:'));
      expect(p, contains('User: hi team'));
      // The load-bearing one: an agent sees another agent's reply.
      expect(p, contains('Researcher: I mapped the schema'));
      expect(p, contains('User: what next?'));
      expect(p, contains('Reply as Coder'));
    });

    test('empty history omits the transcript section', () {
      final p = composeBotTurnPrompt(agent, const [], 'hello');
      expect(p, isNot(contains('Conversation so far')));
      expect(p, contains('User: hello'));
    });

    test('keeps only the last 30 transcript lines', () {
      final many = [
        for (var i = 0; i < 40; i++)
          msg([
            {'type': 'text', 'text': 'line$i'}
          ]),
      ];
      final p = composeBotTurnPrompt(agent, many, 'x');
      expect(p, contains('User: line39')); // newest kept
      expect(p, isNot(contains('User: line0'))); // oldest dropped
    });
  });

  group('hasOnlineDesktop (the B0 presence gate)', () {
    BotPresence dev(String role, {required bool online}) => BotPresence.tryParse({
          'deviceId': 'd-$role',
          'role': role,
          'status': online ? 'online' : 'offline',
          'online': online,
        })!;

    test('an online desktop means mobile is NOT the executor', () {
      expect([dev('desktop', online: true)].hasOnlineDesktop, isTrue);
    });

    test('an offline desktop does not count', () {
      expect([dev('desktop', online: false)].hasOnlineDesktop, isFalse);
    });

    test('only mobile online → no online desktop', () {
      expect([dev('mobile', online: true)].hasOnlineDesktop, isFalse);
    });

    test('no devices → no online desktop', () {
      expect(<BotPresence>[].hasOnlineDesktop, isFalse);
    });

    test('mobile + desktop both online → desktop is present', () {
      expect(
        [dev('mobile', online: true), dev('desktop', online: true)]
            .hasOnlineDesktop,
        isTrue,
      );
    });
  });
}
