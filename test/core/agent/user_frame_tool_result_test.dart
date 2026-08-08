import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';

/// The deployed protocol carries a tool's OUTCOME inside a `user` frame, not
/// as a top-level `tool_result`. We only parsed the top-level form, so every
/// server-executed tool's result was dropped — which is why a refused
/// `net_scan` showed a red card with no reason anywhere on it.
void main() {
  group('user frames carrying tool_result', () {
    test('a failure keeps its reason, unwrapped', () {
      final frame = AgentFrame.tryParse({
        'type': 'user',
        'seq': 12,
        'message': {
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_1',
              'is_error': true,
              'content': '<tool_use_error>Target 8.8.8.8 is outside the '
                  'authorized scope</tool_use_error>',
            },
          ],
        },
      });

      expect(frame, isA<AgentToolResult>());
      final r = frame! as AgentToolResult;
      expect(r.callId, 'toolu_1');
      expect(r.ok, isFalse);
      // Unwrapped here rather than at render time, so the card, the transcript
      // and the saved run all show the same string.
      expect(r.error, 'Target 8.8.8.8 is outside the authorized scope');
      expect(r.error, isNot(contains('tool_use_error')));
    });

    test('a success carries its output', () {
      final frame = AgentFrame.tryParse({
        'type': 'user',
        'message': {
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_2',
              'content': 'total 15',
            },
          ],
        },
      });

      final r = frame! as AgentToolResult;
      expect(r.ok, isTrue);
      expect(r.output, 'total 15');
      expect(r.error, isNull);
    });

    test('content that is a list of blocks, not a string', () {
      final frame = AgentFrame.tryParse({
        'type': 'user',
        'message': {
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_3',
              'content': [
                {'type': 'text', 'text': 'line one\n'},
                {'type': 'text', 'text': 'line two'},
              ],
            },
          ],
        },
      });

      expect((frame! as AgentToolResult).output, 'line one\nline two');
    });

    test('an ordinary user message is not a tool result', () {
      // The same frame type carries the user's own turn. Treating that as a
      // result would invent outcomes for calls that never happened.
      expect(
        AgentFrame.tryParse({
          'type': 'user',
          'message': {
            'content': [
              {'type': 'text', 'text': 'run ls'},
            ],
          },
        }),
        isNull,
      );
    });

    test('a malformed frame is ignored rather than throwing', () {
      expect(AgentFrame.tryParse({'type': 'user'}), isNull);
      expect(
        AgentFrame.tryParse({'type': 'user', 'message': 'nope'}),
        isNull,
      );
      expect(
        AgentFrame.tryParse({
          'type': 'user',
          'message': {
            'content': [
              {'type': 'tool_result'},
            ],
          },
        }),
        isNull,
        reason: 'no tool_use_id — nothing to attach the result to',
      );
    });
  });
}
