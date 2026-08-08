import 'package:cyberneurova_mobile/core/agent/device/tools/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical content produces no diff', () {
    expect(unifiedDiff('a\nb\n', 'a\nb\n'), '');
    expect(unifiedDiff('', ''), '');
  });

  test('a pure addition shows only + lines', () {
    final d = unifiedDiff('a\nb\n', 'a\nb\nc\n');
    expect(d, contains('+ c'));
    expect(d, isNot(contains('- ')));
  });

  test('a pure deletion shows only - lines', () {
    final d = unifiedDiff('a\nb\nc\n', 'a\nb\n');
    expect(d, contains('- c'));
    expect(d.split('\n').where((l) => l.startsWith('+ ')), isEmpty);
  });

  test('a changed line shows both sides', () {
    final d = unifiedDiff('a\nold\nc\n', 'a\nnew\nc\n');
    expect(d, contains('- old'));
    expect(d, contains('+ new'));
    expect(d, contains('  a'));
  });

  test('creating a file from nothing is all additions', () {
    final d = unifiedDiff('', 'hello\nworld\n');
    expect(d, contains('+ hello'));
    expect(d, contains('+ world'));
  });

  test('unchanged regions far from a change are omitted', () {
    final before = List.generate(50, (i) => 'line$i').join('\n');
    final after = before.replaceFirst('line25', 'CHANGED');
    final d = unifiedDiff(before, after);
    expect(d, contains('+ CHANGED'));
    // line0 is 25 lines away; it must not be carried along.
    expect(d, isNot(contains('  line0\n')));
  });

  test('output is capped and says how much was dropped', () {
    final before = List.generate(400, (i) => 'a$i').join('\n');
    final after = List.generate(400, (i) => 'b$i').join('\n');
    final d = unifiedDiff(before, after, maxLines: 20);
    final lines = d.split('\n');
    expect(lines.length, lessThanOrEqualTo(21));
    expect(lines.last, matches(RegExp(r'@@ \d+ more lines? @@')));
  });

  test('a very large pair degrades instead of hanging', () {
    // Above the LCS guard: it must return a summary, not attempt 25M cells.
    final before = List.generate(5000, (i) => 'x$i').join('\n');
    final after = List.generate(5000, (i) => 'y$i').join('\n');
    final d = unifiedDiff(before, after);
    expect(d, contains('file replaced'));
    expect(d, contains('-5000 lines'));
    expect(d, contains('+5000 lines'));
  });

  test('hunk headers carry 1-based line numbers', () {
    final d = unifiedDiff('a\nb\nc\n', 'a\nB\nc\n');
    expect(d, contains(RegExp(r'@@ -\d+ \+\d+ @@')));
    expect(d, isNot(contains('@@ -0 ')));
  });

  group('looksLikeDiff', () {
    test('recognises real diff output', () {
      expect(looksLikeDiff(unifiedDiff('a\n', 'b\n')), isTrue);
    });

    test('does not fire on ordinary tool output', () {
      // A shell result full of dashes must not be coloured as a diff.
      expect(looksLikeDiff('-rw-r--r-- 1 root root 42 notes.md'), isFalse);
      expect(looksLikeDiff('--- nothing here ---'), isFalse);
      expect(looksLikeDiff(''), isFalse);
    });
  });
}
