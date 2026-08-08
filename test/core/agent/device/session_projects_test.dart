import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';

void main() {
  late Directory root;
  late ShellWorkspaceRegistry reg;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cn_projects_test');
    reg = ShellWorkspaceRegistry(rootDir: root.path);
  });

  tearDown(() async {
    await reg.killAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('projects', () {
    test('a fresh session has none', () {
      expect(reg.attach('s1').projects(), isEmpty);
    });

    test('a directory in the session IS a project', () {
      // No manifest and no convention the model has to be taught: it runs
      // `mkdir snake-game` because that is what anyone would do.
      final ws = reg.attach('s1');
      Directory('${ws.sessionDir}/snake-game').createSync(recursive: true);
      File('${ws.sessionDir}/snake-game/index.html').writeAsStringSync('<h1>');

      final projects = ws.projects();

      expect(projects.map((p) => p.name), ['snake-game']);
      expect(projects.single.fileCount, 1);
      expect(projects.single.summary, '1 file');
      expect(projects.single.path, '${ws.sessionDir}/snake-game');
    });

    test('loose files are not projects', () {
      final ws = reg.attach('s1');
      File('${ws.sessionDir}/notes.txt').writeAsStringSync('x');
      expect(ws.projects(), isEmpty);
    });

    test('hidden directories are the environment, not the user', () {
      // .cache and .config are not things anyone built.
      final ws = reg.attach('s1');
      Directory('${ws.sessionDir}/.cache').createSync(recursive: true);
      expect(ws.projects(), isEmpty);
    });

    test('most recently touched first', () async {
      // What you were last working on is what you want at the top of the list.
      final ws = reg.attach('s1');
      Directory('${ws.sessionDir}/old').createSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      Directory('${ws.sessionDir}/new').createSync(recursive: true);

      expect(ws.projects().map((p) => p.name), ['new', 'old']);
    });

    test("one session cannot see another's projects", () {
      final a = reg.attach('s1');
      final b = reg.attach('s2');
      Directory('${a.sessionDir}/mine').createSync(recursive: true);

      expect(a.projects().map((p) => p.name), ['mine']);
      expect(b.projects(), isEmpty);
    });
  });

  group('remove', () {
    test('keepFiles leaves the work on disk', () async {
      // Closing a conversation and destroying the only copy of what it built
      // are different intentions. On a phone there is no second machine the
      // work was synced to.
      final ws = reg.attach('s1');
      final dir = ws.sessionDir;
      Directory('$dir/game').createSync(recursive: true);

      await reg.remove('s1', keepFiles: true);

      expect(reg.all.map((w) => w.id), isNot(contains('s1')));
      expect(Directory('$dir/game').existsSync(), isTrue);
    });

    test('without keepFiles the session directory goes', () async {
      final ws = reg.attach('s1');
      final dir = ws.sessionDir;
      Directory('$dir/game').createSync(recursive: true);

      await reg.remove('s1', keepFiles: false);

      expect(Directory(dir).existsSync(), isFalse);
    });

    test('removing an unknown session is not an error', () async {
      await reg.remove('nope', keepFiles: false);
    });
  });

  group('migrateLegacyFiles', () {
    test('moves work left in the shared home into a legacy session', () {
      // Before sessions existed everything landed here. After an upgrade those
      // files would otherwise sit outside every session — on disk, absent from
      // the app, indistinguishable from data loss.
      File('${root.path}/snake.html').writeAsStringSync('<h1>');
      Directory('${root.path}/scan-report').createSync();

      final moved = reg.migrateLegacyFiles(homeOverride: root.path);

      expect(moved, 2);
      expect(File('${root.path}/sessions/legacy/snake.html').existsSync(),
          isTrue);
      expect(Directory('${root.path}/sessions/legacy/scan-report').existsSync(),
          isTrue);
      expect(File('${root.path}/snake.html').existsSync(), isFalse);
    });

    test('never moves the sessions directory into itself', () {
      reg.attach('s1');
      final moved = reg.migrateLegacyFiles(homeOverride: root.path);
      expect(moved, 0);
      expect(Directory('${root.path}/sessions').existsSync(), isTrue);
    });

    test('leaves dotfiles alone', () {
      File('${root.path}/.profile').writeAsStringSync('x');
      expect(reg.migrateLegacyFiles(homeOverride: root.path), 0);
      expect(File('${root.path}/.profile').existsSync(), isTrue);
    });

    test('is idempotent, and never overwrites', () {
      File('${root.path}/a.txt').writeAsStringSync('first');
      expect(reg.migrateLegacyFiles(homeOverride: root.path), 1);
      expect(reg.migrateLegacyFiles(homeOverride: root.path), 0);

      // A second file of the same name appearing later must not clobber the
      // migrated one — that would destroy the thing this exists to save.
      File('${root.path}/a.txt').writeAsStringSync('second');
      expect(reg.migrateLegacyFiles(homeOverride: root.path), 0);
      expect(
        File('${root.path}/sessions/legacy/a.txt').readAsStringSync(),
        'first',
      );
    });
  });
}
