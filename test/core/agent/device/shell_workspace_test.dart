import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/core/agent/device/background_runs.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_scrollback.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';

/// The scrollback is the "one history" half of the shared-session invariant
/// (`docs/shell/00-OVERVIEW.md` §1) and the thing that lets the agent see what
/// the user typed. Both properties are worth locking down.
void main() {
  // Creating a workspace publishes its session count to the process-wide
  // BackgroundRuns singleton, which in flutter test's single shared isolate
  // otherwise carries a debounce Timer and stale counters between test files.
  // Reset around every test so this file neither inherits nor leaks that state
  // — the shell suite went red only in the FULL suite on a macOS/CI host
  // (outbox 067), which is the signature of exactly this cross-file leak.
  setUp(BackgroundRuns.instance.resetForTest);
  tearDown(BackgroundRuns.instance.resetForTest);

  group('ShellScrollback', () {
    test('splits multi-line output into addressable lines', () {
      final s = ShellScrollback();
      s.append('one\ntwo\nthree', source: ShellLineSource.user);
      expect(s.length, 3);
      expect(s.lines.map((l) => l.text), ['one', 'two', 'three']);
    });

    test('keeps interior blanks but drops a single trailing newline', () {
      final s = ShellScrollback();
      s.append('a\n\nb\n', source: ShellLineSource.user);
      expect(s.lines.map((l) => l.text), ['a', '', 'b']);
    });

    test('is bounded — old lines evict rather than growing forever', () {
      final s = ShellScrollback(maxLines: 10);
      for (var i = 0; i < 50; i++) {
        s.append('line$i', source: ShellLineSource.user);
      }
      expect(s.length, 10);
      expect(s.lines.first.text, 'line40', reason: 'oldest evicted');
      expect(s.lines.last.text, 'line49');
    });

    test('streams each appended line for incremental rendering', () async {
      final s = ShellScrollback();
      final seen = <String>[];
      final sub = s.stream.listen((l) => seen.add(l.text));
      s.append('x\ny', source: ShellLineSource.agent);
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['x', 'y']);
      await sub.cancel();
    });

    test('marks only the first line of a command as the command', () {
      final s = ShellScrollback();
      s.appendCommand('ls -la', source: ShellLineSource.user);
      expect(s.lines.single.isCommand, isTrue);
    });
  });

  group('ShellScrollback.transcript (what the model sees)', () {
    test('distinguishes user, agent and system lines', () {
      final s = ShellScrollback();
      s.appendCommand('cd /opt', source: ShellLineSource.user);
      s.appendCommand('ls', source: ShellLineSource.agent);
      s.append('report.md', source: ShellLineSource.agent);
      s.appendSystem('Shell exited.');

      final t = s.transcript();
      expect(t, contains('\$ cd /opt'));
      expect(t, contains('[agent] \$ ls'));
      expect(t, contains('  report.md'));
      expect(t, contains('# Shell exited.'));
    });

    test('keeps the TAIL and says when it trimmed', () {
      final s = ShellScrollback();
      for (var i = 0; i < 500; i++) {
        s.append('line$i', source: ShellLineSource.user);
      }
      final t = s.transcript(maxLines: 20);
      expect(t, contains('line499'), reason: 'recent state is what matters');
      expect(t, isNot(contains('line100')));
    });

    test('announces truncation rather than silently cutting history', () {
      final s = ShellScrollback();
      s.append('x' * 20000, source: ShellLineSource.user);
      final t = s.transcript(maxChars: 500);
      expect(t, contains('earlier output trimmed'));
      expect(t.length, lessThan(700));
    });
  });

  group('ShellWorkspaceRegistry (the tmux server)', () {
    late Directory root;
    late ShellWorkspaceRegistry reg;

    setUp(() {
      root = Directory.systemTemp.createTempSync('cn_ws_test');
      reg = ShellWorkspaceRegistry(rootDir: root.path);
    });

    tearDown(() async {
      await reg.killAll();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('creates named sessions and lists them', () {
      reg.create(id: 'a');
      reg.create(id: 'b', name: 'recon');
      expect(reg.all.length, 2);
      expect(reg.byId('b')!.name, 'recon');
      expect(reg.byId('a')!.name, startsWith('shell-'));
    });

    test('attach re-uses an existing session instead of forking it', () {
      final first = reg.attach('s1');
      first.shell.changeDirectory('.');
      final again = reg.attach('s1');
      expect(identical(first, again), isTrue,
          reason: 'reattaching must not spawn a second session');
      expect(reg.all.length, 1);
    });

    test('scrollback survives detach — the whole point of a multiplexer', () {
      final ws = reg.attach('s1');
      ws.scrollback.appendCommand('echo hi', source: ShellLineSource.user);
      // "Detach": drop every reference a screen would hold.
      final reattached = reg.attach('s1');
      expect(reattached.scrollback.lines.first.text, 'echo hi');
    });

    test('agent commands land in the same scrollback, marked as agent', () {
      final ws = reg.attach('s1');
      ws.scrollback.appendCommand('ls', source: ShellLineSource.user);
      ws.active.recordAgentCommand('nmap -sT 10.0.0.1', 'port 22 open');

      final sources = ws.scrollback.lines.map((l) => l.source).toList();
      expect(sources, contains(ShellLineSource.user));
      expect(sources, contains(ShellLineSource.agent));
      // And the agent can read back what the user did.
      expect(ws.scrollback.transcript(), contains('\$ ls'));
      expect(ws.scrollback.transcript(), contains('[agent] \$ nmap'));
    });

    test('kill removes the session', () async {
      reg.create(id: 'x');
      await reg.kill('x');
      expect(reg.byId('x'), isNull);
      expect(reg.all, isEmpty);
    });
  });

  group('panes (tmux window layer)', () {
    late Directory root;
    late ShellWorkspaceRegistry reg;
    late ShellWorkspace ws;

    setUp(() {
      root = Directory.systemTemp.createTempSync('cn_pane_test');
      reg = ShellWorkspaceRegistry(rootDir: root.path);
      ws = reg.attach('s1');
      // Inside the SESSION's directory, not the shared root: that is where a
      // pane now starts, so a fixture at the root would be unreachable by a
      // relative `cd` — which is the whole point of the change.
      Directory('${ws.sessionDir}/sub').createSync(recursive: true);
    });

    tearDown(() async {
      await reg.killAll();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a session always starts with exactly one pane', () {
      expect(ws.paneCount, 1);
      expect(ws.active, isNotNull);
    });

    test('newPane adds and focuses it', () {
      final p = ws.newPane(title: 'scan');
      expect(ws.paneCount, 2);
      expect(ws.active.id, p.id);
      expect(ws.active.title, 'scan');
    });

    test('a new pane inherits the current cwd, like tmux split -c', () {
      ws.active.shell.changeDirectory('sub');
      final expected = ws.active.shell.cwd;
      final p = ws.newPane();
      expect(p.shell.cwd, expected,
          reason: 'you split to run a second thing HERE');
    });

    test('panes keep independent cwds after splitting', () {
      ws.newPane();                       // pane 2, focused
      ws.active.shell.changeDirectory('sub');
      final second = ws.active.shell.cwd;
      ws.selectPane(0);
      expect(ws.active.shell.cwd, isNot(second),
          reason: 'each pane owns its own working directory');
    });

    test('a session gets its own directory, not the shared root', () {
      // The bug this closes: every session started in one home, so an `ls`
      // showed artefacts from unrelated sessions in a single flat pile and
      // nothing could be called "the project".
      expect(ws.sessionDir, isNot(root.path));
      expect(ws.sessionDir, contains('sessions'));
      expect(Directory(ws.sessionDir).existsSync(), isTrue,
          reason: 'created eagerly — a cwd that does not exist makes every '
              'relative path in the session wrong');
      expect(ws.active.shell.cwd, ws.sessionDir);
    });

    test('two sessions do not share a directory', () {
      final other = reg.attach('s2');
      expect(other.sessionDir, isNot(ws.sessionDir));
    });

    test('next/previous wrap around', () {
      ws.newPane();
      ws.newPane();                       // 3 panes, index 2
      expect(ws.activeIndex, 2);
      ws.nextPane();
      expect(ws.activeIndex, 0, reason: 'wraps');
      ws.previousPane();
      expect(ws.activeIndex, 2, reason: 'wraps backwards');
    });

    test('selectPaneById focuses the right pane', () {
      final p = ws.newPane(title: 'x');
      ws.selectPane(0);
      expect(ws.selectPaneById(p.id), isTrue);
      expect(ws.active.id, p.id);
      expect(ws.selectPaneById('nope'), isFalse);
    });

    test('closing a pane focuses a neighbour, not index 0', () async {
      ws.newPane();                       // idx 1
      final third = ws.newPane();         // idx 2 (focused)
      ws.selectPane(1);
      await ws.closePane(third.id);
      expect(ws.paneCount, 2);
      expect(ws.activeIndex, lessThan(2));
    });

    test('closing the LAST pane opens a fresh one instead of stranding', () async {
      await ws.closePane(ws.active.id);
      expect(ws.paneCount, 1, reason: 'never leave a session with no pane');
      expect(ws.active, isNotNull);
    });

    test('workspace.shell/scrollback follow the ACTIVE pane', () {
      ws.active.scrollback.appendSystem('first');
      final p2 = ws.newPane();
      p2.scrollback.appendSystem('second');
      expect(ws.scrollback.lines.last.text, 'second');
      ws.selectPane(0);
      expect(ws.scrollback.lines.last.text, 'first');
      expect(identical(ws.shell, ws.active.shell), isTrue);
    });
  });
}
