import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/tool_call_leak.dart';

void main() {
  group('stripToolCallTemplates', () {
    test('leaves ordinary prose exactly as it was', () {
      const prose = 'I called the shop and they said it will be ready at 5.';
      final out = stripToolCallTemplates(prose);
      expect(out.text, prose);
      expect(out.didStrip, isFalse);
    });

    test('strips the template prod actually sent, and names the tool', () {
      // Verbatim from a run against prod, 2026-08-04.
      const leaked = '<|tool_call>call:Write{path:<|"|>hello.txt<|"|>,'
          'content:<|"|>hi<|"|>}<tool_call|>';

      final out = stripToolCallTemplates(leaked);

      expect(out.toolNames, ['Write']);
      // Nothing recognisable from the template survives — not the delimiters,
      // not the tool name, not the value quoting.
      expect(out.text, isEmpty);
      expect(out.isOnlyToolCall, isTrue);
    });

    test('keeps the prose a model wrote around a template', () {
      const mixed = 'Sure, writing that now. '
          '<|tool_call>call:Write{path:<|"|>a.txt<|"|>}<tool_call|>'
          ' Let me know if you want it elsewhere.';

      final out = stripToolCallTemplates(mixed);

      expect(out.text, contains('Sure, writing that now.'));
      expect(out.text, contains('Let me know if you want it elsewhere.'));
      expect(out.text, isNot(contains('call:')));
      expect(out.isOnlyToolCall, isFalse);
    });

    test('drops a template that is still being written', () {
      // This runs on every partial frame, so the half-written state is the
      // common case, not the edge one. Without this the delimiter and a
      // half-spelled tool name flash on screen mid-stream.
      const partial = 'One moment. <|tool_call>call:Wri';

      final out = stripToolCallTemplates(partial);

      expect(out.text, 'One moment.');
      expect(out.text, isNot(contains('<|')));
    });

    test('strips the bare form the older leak used', () {
      const bare = 'call:Skill{name:deploy,args:{env:prod}}';

      final out = stripToolCallTemplates(bare);

      expect(out.toolNames, ['Skill']);
      expect(out.text, isEmpty);
    });

    test('scans braces rather than matching lazily', () {
      // A value containing a brace would end a lazy regex early and leave the
      // tail of the template on screen.
      const nested = 'Done. call:Write{content:{"a":{"b":1}},path:x} Anything else?';

      final out = stripToolCallTemplates(nested);

      expect(out.text, 'Done.  Anything else?'.trim());
      expect(out.text, isNot(contains('path:x')));
      expect(out.text, isNot(contains('}')));
    });

    test('handles more than one call in a single message', () {
      const two = '<|tool_call>call:Read{path:<|"|>a<|"|>}<tool_call|>'
          '<|tool_call>call:Write{path:<|"|>b<|"|>}<tool_call|>';

      final out = stripToolCallTemplates(two);

      expect(out.toolNames, ['Read', 'Write']);
      expect(out.text, isEmpty);
    });

    test('does not fire on prose that merely mentions calling', () {
      const talking = 'You can call: the office, or email them instead.';
      final out = stripToolCallTemplates(talking);
      expect(out.didStrip, isFalse);
      expect(out.text, talking);
    });

    test('does not fire on code that happens to contain a call', () {
      // A model explaining code should not have it eaten.
      const code = 'Use `client.call(x)` and then `{ret: 1}` comes back.';
      final out = stripToolCallTemplates(code);
      expect(out.didStrip, isFalse);
      expect(out.text, code);
    });
  });
  group('stripThinkTags', () {
    test('removes a stray closer left at the top of a reply', () {
      // Seen on prod as the entire visible answer: the serving layer stripped
      // the opener but not the closer.
      expect(stripThinkTags('</think>'), isEmpty);
      expect(
        stripThinkTags('</think>\n\nHere is the answer.'),
        'Here is the answer.',
      );
    });

    test('removes a whole reasoning block but keeps the answer', () {
      const raw = '<think>the user wants a file</think>Done — wrote notes.txt.';
      expect(stripThinkTags(raw), 'Done — wrote notes.txt.');
    });

    test('hides reasoning that has not closed yet', () {
      // Mid-stream the closer has not arrived. Rendering what is there would
      // show the user the model's private reasoning.
      expect(stripThinkTags('<think>let me check whether'), isEmpty);
    });

    test('leaves prose about thinking alone', () {
      const prose = 'I was thinking we could use a queue here.';
      expect(stripThinkTags(prose), prose);
    });
  });
  group('stripToolCallTemplates — the <tool_code> dialect', () {
    test('strips the form seen on prod, naming the tool from the tag', () {
      // Verbatim shape from a run on 2026-08-04. Unlike the others the tool is
      // named in the OPENING tag and the body is a bare command.
      const leaked = '<tool_code:Bash>\n'
          "ls -F done.txt > /dev/null && grep -v 'x' done.txt\n"
          '</tool_code>';

      final out = stripToolCallTemplates(leaked);

      expect(out.toolNames, ['Bash']);
      expect(out.text, isEmpty);
      expect(out.isOnlyToolCall, isTrue);
    });

    test('keeps prose written around it', () {
      const mixed = 'Let me check.\n<tool_code:Bash>ls</tool_code>\nAll set.';
      final out = stripToolCallTemplates(mixed);

      expect(out.text, contains('Let me check.'));
      expect(out.text, contains('All set.'));
      expect(out.text, isNot(contains('ls')));
    });

    test('drops one that is still streaming', () {
      final out = stripToolCallTemplates('One sec. <tool_code:Bash>ls -');
      expect(out.text, 'One sec.');
      expect(out.didStrip, isTrue);
    });

    test('handles the unnamed variant without inventing a name', () {
      final out = stripToolCallTemplates('<tool_code>whoami</tool_code>');
      expect(out.toolNames, ['a tool']);
      expect(out.text, isEmpty);
    });

    test('leaves ordinary prose and code alone', () {
      const prose = 'The tool code lives in tools/ and is easy to read.';
      expect(stripToolCallTemplates(prose).didStrip, isFalse);
    });
  });
  group('stripSystemDirectives', () {
    test('removes the retry instruction the server injects', () {
      // Verbatim from a run on 2026-08-04. Addressed to the model, rendered to
      // the user as if it were the answer.
      const leaked = '[system: your "shell_exec" tool call could not be parsed '
          'and did not run — re-issue it as a tool_code:ToolName block with '
          'valid arguments]';
      expect(stripSystemDirectives(leaked), isEmpty);
    });

    test('keeps the prose around it', () {
      const mixed = 'Let me try that again. '
          '[system: the call could not be parsed] Done.';
      final out = stripSystemDirectives(mixed);
      expect(out, contains('Let me try that again.'));
      expect(out, contains('Done.'));
      expect(out, isNot(contains('system:')));
    });

    test('drops one that is still streaming', () {
      // Unterminated mid-stream: the closing bracket has not arrived, and
      // showing the opener would flash machine text at the user.
      expect(stripSystemDirectives('[system: your call could not'), isEmpty);
    });

    test('leaves ordinary bracketed prose alone', () {
      const prose = 'The config uses [system] as a section header.';
      expect(stripSystemDirectives(prose), prose);
    });
  });
}
