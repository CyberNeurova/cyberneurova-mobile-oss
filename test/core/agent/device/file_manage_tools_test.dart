import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/file_manage_tools.dart';

void main() {
  late Directory root;
  late ShellSession session;

  DeviceToolContext ctx() => DeviceToolContext(
        capabilities: const DeviceCapabilities(
          platform: 'android',
          osVersion: '16',
          present: {DeviceCapability.fileSandbox},
        ),
        scope: const AuthorizedScope.empty(),
        localSubnetCidrs: const [],
        onProgress: (_) {},
        isCancelled: () => false,
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('manage_tools');
    session = ShellSession(rootDir: root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File file(String rel, [String body = 'x']) =>
      File(p.join(root.path, rel))..writeAsStringSync(body);

  group('file_move', () {
    test('renames a file', () async {
      file('a.txt', 'body');
      final r = await FileMoveTool(session: session).run(
        {'from': p.join(root.path, 'a.txt'), 'to': p.join(root.path, 'b.txt')},
        ctx(),
      );

      expect(r.ok, isTrue);
      expect(File(p.join(root.path, 'b.txt')).readAsStringSync(), 'body');
      expect(File(p.join(root.path, 'a.txt')).existsSync(), isFalse);
    });

    test('moving onto a directory means INTO it', () async {
      // What everyone expects from `mv a.txt somedir`, and what an agent will
      // assume. Without it the directory would be replaced by the file.
      file('a.txt');
      Directory(p.join(root.path, 'box')).createSync();

      final r = await FileMoveTool(session: session).run(
        {'from': p.join(root.path, 'a.txt'), 'to': p.join(root.path, 'box')},
        ctx(),
      );

      expect(r.ok, isTrue);
      expect(File(p.join(root.path, 'box', 'a.txt')).existsSync(), isTrue);
    });

    test('will not silently clobber', () async {
      file('a.txt', 'new');
      file('b.txt', 'precious');

      final r = await FileMoveTool(session: session).run(
        {'from': p.join(root.path, 'a.txt'), 'to': p.join(root.path, 'b.txt')},
        ctx(),
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('already exists'));
      expect(File(p.join(root.path, 'b.txt')).readAsStringSync(), 'precious');
    });

    test('overwrite: true is honoured when asked for explicitly', () async {
      file('a.txt', 'new');
      file('b.txt', 'old');

      final r = await FileMoveTool(session: session).run(
        {
          'from': p.join(root.path, 'a.txt'),
          'to': p.join(root.path, 'b.txt'),
          'overwrite': true,
        },
        ctx(),
      );

      expect(r.ok, isTrue);
      expect(File(p.join(root.path, 'b.txt')).readAsStringSync(), 'new');
    });

    test('creates missing parents on the way', () async {
      file('a.txt');
      final r = await FileMoveTool(session: session).run(
        {
          'from': p.join(root.path, 'a.txt'),
          'to': p.join(root.path, 'deep', 'er', 'a.txt'),
        },
        ctx(),
      );
      expect(r.ok, isTrue);
      expect(File(p.join(root.path, 'deep', 'er', 'a.txt')).existsSync(),
          isTrue);
    });

    test('refuses to move anything out of the session', () async {
      file('a.txt');
      final r = await FileMoveTool(session: session).run(
        {'from': p.join(root.path, 'a.txt'), 'to': '${root.path}/../escaped'},
        ctx(),
      );
      expect(r.ok, isFalse);
      expect(r.error, contains('outside the session'));
    });

    test('refuses to move the session root itself', () async {
      final r = await FileMoveTool(session: session).run(
        {'from': root.path, 'to': p.join(root.path, 'x')},
        ctx(),
      );
      expect(r.ok, isFalse);
      expect(r.error, contains('session directory itself'));
    });
  });

  group('file_delete', () {
    test('deletes a file and says how much went', () async {
      file('gone.txt', '12345');
      final r = await FileDeleteTool(session: session)
          .run({'path': p.join(root.path, 'gone.txt')}, ctx());

      expect(r.ok, isTrue);
      expect(r.output, contains('5 bytes'));
      expect(File(p.join(root.path, 'gone.txt')).existsSync(), isFalse);
    });

    test('a non-empty directory needs saying so out loud', () async {
      // The accident this prevents: meaning to remove one stale file and
      // naming its parent. There is no undo and no trash can.
      Directory(p.join(root.path, 'work')).createSync();
      file(p.join('work', 'important.txt'), 'do not lose me');

      final r = await FileDeleteTool(session: session)
          .run({'path': p.join(root.path, 'work')}, ctx());

      expect(r.ok, isFalse);
      expect(r.error, contains('not empty'));
      expect(r.error, contains('no undo'));
      expect(
        File(p.join(root.path, 'work', 'important.txt')).existsSync(),
        isTrue,
      );
    });

    test('an empty directory goes without ceremony', () async {
      Directory(p.join(root.path, 'empty')).createSync();
      final r = await FileDeleteTool(session: session)
          .run({'path': p.join(root.path, 'empty')}, ctx());
      expect(r.ok, isTrue);
    });

    test('recursive: true does what it says', () async {
      Directory(p.join(root.path, 'work')).createSync();
      file(p.join('work', 'a.txt'));

      final r = await FileDeleteTool(session: session).run(
          {'path': p.join(root.path, 'work'), 'recursive': true}, ctx());

      expect(r.ok, isTrue);
      expect(Directory(p.join(root.path, 'work')).existsSync(), isFalse);
    });

    test('refuses the session root even with recursive', () async {
      final r = await FileDeleteTool(session: session)
          .run({'path': root.path, 'recursive': true}, ctx());

      expect(r.ok, isFalse);
      expect(r.error, contains('session directory itself'));
      expect(root.existsSync(), isTrue);
    });

    test('refuses anything outside the session', () async {
      final r = await FileDeleteTool(session: session)
          .run({'path': '${root.path}/../..'}, ctx());
      expect(r.ok, isFalse);
      expect(r.error, contains('outside the session'));
    });
  });

  group('file_mkdir', () {
    test('creates parents in one go', () async {
      final r = await FileMkdirTool(session: session)
          .run({'path': p.join(root.path, 'src', 'main', 'app')}, ctx());

      expect(r.ok, isTrue);
      expect(
        Directory(p.join(root.path, 'src', 'main', 'app')).existsSync(),
        isTrue,
      );
    });

    test('already existing is success, not an error', () async {
      // The requested state is the actual state. Failing would make an agent
      // branch on something it does not need to.
      Directory(p.join(root.path, 'here')).createSync();
      final r = await FileMkdirTool(session: session)
          .run({'path': p.join(root.path, 'here')}, ctx());
      expect(r.ok, isTrue);
      expect(r.summary, contains('already exists'));
    });

    test('a file in the way is an error, because it is', () async {
      file('clash');
      final r = await FileMkdirTool(session: session)
          .run({'path': p.join(root.path, 'clash')}, ctx());
      expect(r.ok, isFalse);
      expect(r.error, contains('already exists as a file'));
    });
  });
}
