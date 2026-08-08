import 'package:cyberneurova_mobile/core/agent/device/shell_scrollback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ShellScrollback sb;

  setUp(() => sb = ShellScrollback());
  tearDown(() => sb.dispose());

  List<String> texts() => sb.lines.map((l) => l.text).toList();

  group('appendStream', () {
    test('joins a line split across chunks', () {
      // Measured on device: `uname -a` echoed back as two chunks and rendered
      // as two lines. A chunk boundary is not a line boundary.
      sb.appendStream('un', source: ShellLineSource.user);
      sb.appendStream('ame -a\n', source: ShellLineSource.user);
      expect(texts(), ['uname -a']);
    });

    test('splits on real newlines', () {
      sb.appendStream('one\ntwo\nthree\n', source: ShellLineSource.user);
      expect(texts(), ['one', 'two', 'three']);
    });

    test('keeps interior blank lines but not the terminator', () {
      sb.appendStream('a\n\nb\n', source: ShellLineSource.user);
      expect(texts(), ['a', '', 'b']);
    });

    test('leaves an unterminated tail open for the next chunk', () {
      sb.appendStream('a\nb', source: ShellLineSource.user);
      expect(texts(), ['a', 'b']);
      sb.appendStream('c\n', source: ShellLineSource.user);
      expect(texts(), ['a', 'bc']);
    });

    test('does not continue a line written by a different source', () {
      sb.appendStream('partial', source: ShellLineSource.user);
      sb.appendStream('agent output\n', source: ShellLineSource.agent);
      expect(texts(), ['partial', 'agent output']);
    });

    test('a system message never glues onto an open tail', () {
      // Misattribution would be worse than a cosmetic split: the reader would
      // see our notice as part of the command's output.
      sb.appendStream('half a line', source: ShellLineSource.user);
      sb.appendSystem('Shell exited.');
      expect(texts(), ['half a line', 'Shell exited.']);

      sb.appendStream('more', source: ShellLineSource.user);
      expect(texts(), ['half a line', 'Shell exited.', 'more']);
    });

    test('bumps revision once per chunk, not per line', () {
      final before = sb.revision.value;
      sb.appendStream('a\nb\nc\n', source: ShellLineSource.user);
      expect(sb.revision.value, before + 1);
    });

    test('ignores an empty chunk', () {
      sb.appendStream('', source: ShellLineSource.user);
      expect(sb.lines, isEmpty);
    });

    test('respects maxLines', () {
      final small = ShellScrollback(maxLines: 3);
      small.appendStream('1\n2\n3\n4\n5\n', source: ShellLineSource.user);
      expect(small.lines.map((l) => l.text), ['3', '4', '5']);
      small.dispose();
    });
  });

  group('append', () {
    test('still splits a complete multi-line string', () {
      sb.append('x\ny', source: ShellLineSource.agent);
      expect(texts(), ['x', 'y']);
    });

    test('marks only the first line as the command', () {
      sb.appendCommand('ls -la', source: ShellLineSource.user);
      expect(sb.lines.single.isCommand, isTrue);
    });
  });

  group('transcript', () {
    test('marks provenance so the agent can tell who did what', () {
      sb.appendCommand('ls', source: ShellLineSource.user);
      sb.appendStream('a.txt\n', source: ShellLineSource.user);
      sb.recordAgentLineForTest();
      final t = sb.transcript();
      expect(t, contains('\$ ls'));
      expect(t, contains('  a.txt'));
      expect(t, contains('[agent] \$ '));
    });

    test('announces truncation rather than silently dropping history', () {
      for (var i = 0; i < 500; i++) {
        sb.appendStream('line $i with some padding text\n',
            source: ShellLineSource.user);
      }
      expect(sb.transcript(maxChars: 200), startsWith('…(earlier output'));
    });
  });
}

extension on ShellScrollback {
  void recordAgentLineForTest() =>
      appendCommand('whoami', source: ShellLineSource.agent);
}
