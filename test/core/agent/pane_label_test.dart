import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/pane_label.dart';

void main() {
  group('ppidFromStat', () {
    test('reads the parent pid from a normal line', () {
      // Real shape: pid (comm) state ppid pgrp …
      const stat = '4242 (sh) S 4200 4242 4242 0 -1 4194304 …';
      expect(ppidFromStat(stat), 4200);
    });

    test('survives an executable name containing spaces and parens', () {
      // Splitting on whitespace returns a plausible WRONG number here, which
      // is worse than returning nothing — the pane would be labelled after
      // some unrelated process.
      const stat = '77 (my prog (2)) S 12 77 77 0 -1 4194304 …';
      expect(ppidFromStat(stat), 12);
    });

    test('returns null on junk rather than guessing', () {
      expect(ppidFromStat(''), isNull);
      expect(ppidFromStat('no parens here'), isNull);
      expect(ppidFromStat('9 (sh)'), isNull);
    });
  });

  group('foregroundFromChain', () {
    test('is null when only the shell is running', () {
      expect(foregroundFromChain(['sh']), isNull);
      expect(foregroundFromChain(['bash', 'sh']), isNull);
    });

    test('names the program the user is looking at', () {
      expect(foregroundFromChain(['sh', 'vim']), 'vim');
    });

    test('takes the deepest process, not the first', () {
      // `git log` opens a pager; `less` is what is on screen.
      expect(foregroundFromChain(['sh', 'git', 'less']), 'less');
    });

    test('ignores empties without falling over', () {
      expect(foregroundFromChain(['sh', '  ', 'htop']), 'htop');
      expect(foregroundFromChain([]), isNull);
    });

    test('skips proot, which is plumbing rather than a program', () {
      expect(foregroundFromChain(['proot', 'bash']), isNull);
      expect(foregroundFromChain(['proot', 'bash', 'nano']), 'nano');
    });
  });

  group('paneLabel', () {
    test('a name the user typed always wins', () {
      expect(
        paneLabel(
          userTitle: 'build',
          foreground: 'cargo',
          shellName: 'bash',
          status: PaneStatus.running,
        ),
        'build',
      );
    });

    test('falls back to the foreground program', () {
      expect(
        paneLabel(
          foreground: 'htop',
          shellName: 'bash',
          status: PaneStatus.running,
        ),
        'htop',
      );
    });

    test('shows the shell when the pane is just sitting at a prompt', () {
      expect(
        paneLabel(shellName: 'bash', status: PaneStatus.running),
        'bash',
      );
    });

    test('ignores a stale foreground once the pane is not running', () {
      // The poll that found `vim` may land after the shell exited; labelling a
      // dead pane `vim` would suggest it is still open.
      expect(
        paneLabel(
          foreground: 'vim',
          shellName: 'bash',
          status: PaneStatus.exited,
        ),
        'bash',
      );
    });

    test('treats a blank user title as no title', () {
      expect(
        paneLabel(
          userTitle: '   ',
          foreground: 'nano',
          shellName: 'sh',
          status: PaneStatus.running,
        ),
        'nano',
      );
    });
  });

  group('PaneStatus', () {
    test('distinguishes the three cases a bool collapsed', () {
      // never-started, ended cleanly, and died must not read the same.
      expect(PaneStatus.idle.description, 'not started');
      expect(PaneStatus.exited.description, 'exited');
      expect(PaneStatus.failed.description, 'failed');
    });
  });
}
