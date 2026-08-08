import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/tool_run_card.dart';

/// The `[TOOL_RUN:{json}]` payload, parsed and summarised.
///
/// This is model-adjacent data: the JSON arrives inside an assistant message
/// written by an LLM, so it is malformed more often than a server contract
/// would be. Both parsers are deliberately defensive — a bad step is skipped
/// rather than thrown, and a run with nothing left renders nothing at all —
/// which means a regression here is silent. The card just stops appearing, or
/// appears empty, and the run still looks like it happened.
///
/// The summary is the one line the user actually reads to find out what the
/// agent did to their device. "Ran 2 commands · edited app.py" is the whole
/// report unless they tap in.
void main() {
  Map<String, dynamic> step(String verb, String target,
          [Map<String, dynamic>? extra]) =>
      {
        'verb': verb,
        'target': target,
        ...?extra,
      };

  group('ToolRunStep.fromJson skips what it cannot trust', () {
    test('a step needs both a verb and a target', () {
      expect(ToolRunStep.fromJson({'target': 'a.py'}), isNull);
      expect(ToolRunStep.fromJson({'verb': 'edit'}), isNull);
      expect(ToolRunStep.fromJson({'verb': '', 'target': 'a.py'}), isNull);
      expect(ToolRunStep.fromJson({'verb': 'edit', 'target': ''}), isNull);
    });

    test('a wrong-typed verb or target is not coerced', () {
      // A model emitting `{"verb": 1}` must not produce a step labelled "1".
      expect(ToolRunStep.fromJson({'verb': 1, 'target': 'a.py'}), isNull);
      expect(ToolRunStep.fromJson({'verb': 'edit', 'target': 42}), isNull);
    });

    test('anything that is not a map is not a step', () {
      expect(ToolRunStep.fromJson('edit a.py'), isNull);
      expect(ToolRunStep.fromJson(null), isNull);
      expect(ToolRunStep.fromJson(['edit']), isNull);
    });

    test('counts arrive as numbers, and only as numbers', () {
      final s = ToolRunStep.fromJson(
          step('edit', 'a.py', {'added': 3, 'removed': 1.0}))!;
      expect(s.added, 3);
      expect(s.removed, 1, reason: 'a double is floored to an int');

      final bad = ToolRunStep.fromJson(step('edit', 'a.py', {'added': '3'}))!;
      expect(bad.added, isNull,
          reason: 'a string count is dropped, not parsed');
    });

    test('empty strings are treated as absent', () {
      final s = ToolRunStep.fromJson(
          step('run', 'ls', {'error': '', 'diff': '', 'output': ''}))!;
      expect(s.error, isNull);
      expect(s.diff, isNull);
      expect(s.output, isNull);
    });

    test('failed is true only when it is exactly true', () {
      expect(ToolRunStep.fromJson(step('run', 'ls'))!.failed, isFalse);
      expect(
          ToolRunStep.fromJson(step('run', 'ls', {'failed': 'true'}))!.failed,
          isFalse,
          reason: 'a string is not a boolean');
      expect(ToolRunStep.fromJson(step('run', 'ls', {'failed': true}))!.failed,
          isTrue);
    });
  });

  group('ToolRun.fromJson', () {
    test('keeps the good steps and drops the bad ones', () {
      final run = ToolRun.fromJson({
        'steps': [
          step('run', 'ls'),
          'garbage',
          {'verb': 'edit'},
          step('read', 'a.py')
        ],
      })!;
      expect(run.steps.map((s) => s.verb), ['run', 'read']);
    });

    test('a run with no usable step is null, not empty', () {
      // An empty card claiming a tool run happened is worse than no card.
      expect(ToolRun.fromJson({'steps': []}), isNull);
      expect(
          ToolRun.fromJson({
            'steps': ['garbage']
          }),
          isNull);
      expect(ToolRun.fromJson({'steps': 'run ls'}), isNull);
      expect(ToolRun.fromJson({}), isNull);
    });

    test('totals and flags aggregate across steps', () {
      final run = ToolRun.fromJson({
        'steps': [
          step('edit', 'a.py', {'added': 3, 'removed': 1}),
          step('edit', 'b.py', {'added': 4}),
          step('run', 'ls', {'failed': true}),
        ],
      })!;
      expect(run.totalAdded, 7);
      expect(run.totalRemoved, 1);
      expect(run.failedCount, 1);
      expect(run.hasEdits, isTrue);
    });

    test('a run with no edits says so', () {
      final run = ToolRun.fromJson({
        'steps': [step('run', 'ls')]
      })!;
      expect(run.hasEdits, isFalse);
      expect(run.totalAdded, 0);
    });
  });

  group('summary — the one line the user reads', () {
    String summaryOf(List<Map<String, dynamic>> steps) =>
        ToolRun.fromJson({'steps': steps})!.summary;

    test('counts per verb, in first-appearance order', () {
      expect(
        summaryOf([
          step('run', 'ls'),
          step('read', 'a.py'),
          step('run', 'pwd'),
          step('read', 'b.py'),
          step('read', 'c.py'),
        ]),
        'Ran 2 commands · read 3 files',
      );
    });

    test('singular and plural are both right', () {
      expect(summaryOf([step('run', 'ls')]), 'Ran 1 command');
      expect(summaryOf([step('read', 'a.py')]), 'Read 1 file');
      expect(summaryOf([step('fetch', 'x.com')]), 'Fetched 1 page');
      expect(summaryOf([step('fetch', 'x.com'), step('fetch', 'y.com')]),
          'Fetched 2 pages');
    });

    test('a single edit names the file, several are counted', () {
      // Naming the file is the point — "edited 1 file" tells you nothing.
      expect(summaryOf([step('edit', '/home/user/app.py')]), 'Edited app.py');
      expect(
        summaryOf([step('edit', 'a.py'), step('edit', 'b.py')]),
        'Edited 2 files',
      );
    });

    test('a bare filename survives having no directory', () {
      expect(summaryOf([step('edit', 'app.py')]), 'Edited app.py');
      expect(summaryOf([step('edit', '/')]), 'Edited /');
    });

    test('search counts occasions rather than files', () {
      expect(summaryOf([step('search', 'TODO')]), 'Searched once');
      expect(
        summaryOf([step('search', 'TODO'), step('search', 'FIXME')]),
        'Searched 2 times',
      );
    });

    test('an unknown verb still reports itself', () {
      // New device tools land server-side before this switch knows them; the
      // card must degrade to something truthful rather than stay silent.
      expect(summaryOf([step('deploy', 'prod')]), 'Deploy 1');
    });

    test('only the first part is capitalised', () {
      expect(
        summaryOf([step('edit', 'a.py'), step('run', 'ls')]),
        'Edited a.py · ran 1 command',
      );
    });
  });
}
