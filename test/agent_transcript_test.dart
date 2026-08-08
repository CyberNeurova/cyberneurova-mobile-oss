import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/tool_presentation.dart';

void main() {
  group('AgentFrame.tryParse', () {
    test('ignores unknown frame types instead of throwing', () {
      expect(AgentFrame.tryParse({'type': 'some_future_frame'}), isNull);
      expect(AgentFrame.tryParse({'no_type': 1}), isNull);
    });

    test('accepts either field name for a tool call', () {
      final a = AgentFrame.tryParse({
        'type': 'tool_call',
        'call_id': 'c1',
        'tool': 'WebSearch',
        'input': {'query': 'x'},
      }) as AgentToolCall;
      final b = AgentFrame.tryParse({
        'type': 'tool_call',
        'id': 'c1',
        'name': 'WebSearch',
        'args': {'query': 'x'},
      }) as AgentToolCall;

      expect(a.callId, 'c1');
      expect(b.callId, 'c1');
      expect(a.tool, b.tool);
      expect(b.input['query'], 'x');
    });

    test('decodes double-encoded JSON tool input', () {
      final frame = AgentFrame.tryParse({
        'type': 'tool_call',
        'call_id': 'c1',
        'tool': 'Bash',
        'input': '{"command":"ls -la"}',
      }) as AgentToolCall;
      expect(frame.input['command'], 'ls -la');
    });

    test('treats can_use_tool as an approval request', () {
      final frame = AgentFrame.tryParse({
        'type': 'can_use_tool',
        'tool_use_id': 'c9',
        'tool_name': 'Bash',
        'input': {'command': 'rm -rf /tmp/x'},
        'decision_reason': 'Destructive command',
      });
      expect(frame, isA<AgentApprovalRequest>());
      expect((frame! as AgentApprovalRequest).rationale, 'Destructive command');
    });
  });

  group('AgentTranscript', () {
    test('accumulates assistant deltas into one message', () {
      final t = AgentTranscript();
      t.apply(const AgentAssistantDelta(text: 'Hello '));
      t.apply(const AgentAssistantDelta(text: 'world'));

      expect(t.items, hasLength(1));
      expect((t.items.single as AssistantMessageItem).text, 'Hello world');
    });

    test('a tool call closes the open prose block', () {
      final t = AgentTranscript();
      t.apply(const AgentAssistantDelta(text: 'Let me look.'));
      t.apply(const AgentToolCall(
          callId: 'c1', tool: 'WebSearch', input: {'query': 'flutter'}));
      t.apply(const AgentAssistantDelta(text: 'Found it.'));

      // message, card, message — narration stays ordered around the action.
      expect(t.items, hasLength(3));
      expect(t.items[0], isA<AssistantMessageItem>());
      expect(t.items[1], isA<ToolCardItem>());
      expect(t.items[2], isA<AssistantMessageItem>());
      expect((t.items[2] as AssistantMessageItem).text, 'Found it.');
    });

    test('progress and result update the matching card', () {
      final t = AgentTranscript();
      t.apply(const AgentToolCall(
          callId: 'c1', tool: 'Bash', input: {'command': 'ls'}));
      t.apply(const AgentToolProgress(callId: 'c1', text: 'a.txt\nb.txt'));
      t.apply(const AgentToolResult(
          callId: 'c1', ok: true, summary: '2 files'));

      final card = t.items.single as ToolCardItem;
      expect(card.state, ToolCardState.succeeded);
      expect(card.summary, '2 files');
      expect(card.progressLines, ['a.txt', 'b.txt']);
      expect(card.endedAt, isNotNull);
    });

    test('frames for an unknown call id are ignored, not crashes', () {
      final t = AgentTranscript();
      expect(t.apply(const AgentToolProgress(callId: 'ghost', text: 'x')),
          isFalse);
      expect(t.apply(const AgentToolResult(callId: 'ghost', ok: true)),
          isFalse);
      expect(t.items, isEmpty);
    });

    test('replayed frames below lastSeq are dropped', () {
      final t = AgentTranscript();
      t.apply(const AgentAssistantDelta(text: 'one', seq: 1));
      t.apply(const AgentAssistantDelta(text: 'two', seq: 2));
      // A reconnect redelivers seq 2 — it must not be applied twice.
      final changed = t.apply(const AgentAssistantDelta(text: 'two', seq: 2));

      expect(changed, isFalse);
      expect((t.items.single as AssistantMessageItem).text, 'onetwo');
      expect(t.lastSeq, 2);
    });

    test('run_finished cancels anything still in flight', () {
      final t = AgentTranscript();
      t.apply(const AgentToolCall(callId: 'c1', tool: 'Bash', input: {}));
      t.apply(const AgentRunFinished());

      expect((t.items.single as ToolCardItem).state, ToolCardState.cancelled);
      expect(t.isRunning, isFalse);
    });

    test('approval flow moves through the right states', () {
      final t = AgentTranscript();
      t.apply(const AgentApprovalRequest(
        callId: 'c1',
        tool: 'Bash',
        input: {'command': 'rm x'},
        rationale: 'Destructive',
      ));
      expect(t.hasPendingApproval, isTrue);

      t.markApproved('c1', editedInput: {'command': 'rm -i x'});
      final card = t.items.single as ToolCardItem;
      expect(card.state, ToolCardState.running);
      expect(card.input['command'], 'rm -i x');
      expect(t.hasPendingApproval, isFalse);
    });

    test('progress tail is bounded', () {
      final t = AgentTranscript();
      t.apply(const AgentToolCall(callId: 'c1', tool: 'Bash', input: {}));
      for (var i = 0; i < 500; i++) {
        t.apply(AgentToolProgress(callId: 'c1', text: 'line $i'));
      }
      final card = t.items.single as ToolCardItem;
      expect(card.progressLines.length, lessThanOrEqualTo(200));
      // Oldest dropped, newest kept.
      expect(card.progressLines.last, 'line 499');
    });
  });

  group('ToolPresentation', () {
    test('resolves known tools across naming conventions', () {
      for (final name in ['WebSearch', 'WebSearchTool', 'web_search']) {
        expect(ToolPresentation.of(name).label, 'Web search',
            reason: 'failed for "$name"');
      }
    });

    test('derives something readable for an unknown tool', () {
      // The whole point: a tool this build has never heard of still renders.
      // These names are deliberately absent from the known map — an MCP
      // server could introduce either after this build shipped.
      final snake = ToolPresentation.of('quantum_flux_reader');
      expect(snake.label, 'Quantum flux reader');
      expect(snake.runningVerb, 'Running quantum flux reader');

      final camel = ToolPresentation.of('SomeNewThingTool');
      expect(camel.label, 'Some new thing');
    });

    test('summarizes args by priority, then convention, then anything', () {
      final ws = ToolPresentation.of('WebSearch');
      expect(summarizeToolArgs({'query': 'dart'}, ws), 'dart');

      final unknown = ToolPresentation.of('mystery');
      // No primary keys and no conventional names — falls back to key: value.
      expect(summarizeToolArgs({'wibble': 42}, unknown), 'wibble: 42');
      expect(summarizeToolArgs({}, unknown), isNull);
    });

    test('arg rows keep structured values visible', () {
      final rows = toolArgRows({
        'target': '10.0.0.0/24',
        'opts': {'a': 1, 'b': 2},
        'ports': [1, 2, 3, 4],
      });
      expect(rows, hasLength(3));
      // Nothing renders as empty — an approver must see every field.
      for (final r in rows) {
        expect(r.value, isNotEmpty);
      }
    });
  });
}
