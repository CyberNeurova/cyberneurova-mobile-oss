import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/file_browser.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

void main() {
  late Directory root;
  late FileBrowser browser;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cn_write_back');
    browser = FileBrowser(ShellSession(rootDir: root.path));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('write', () {
    test('saves an edit back to the file', () {
      File('${root.path}/main.dart').writeAsStringSync('void main() {}');

      expect(
          browser.write('${root.path}/main.dart', 'void main() { print(1); }'),
          isNull);
      expect(
        File('${root.path}/main.dart').readAsStringSync(),
        'void main() { print(1); }',
      );
    });

    test('refuses to escape the session directory', () {
      // The same boundary as reading — not a second one that could drift from
      // it. `cd` would refuse to go here, so a save must too.
      final outside = File('${root.path}/../escaped.txt');
      expect(browser.write('${root.path}/../escaped.txt', 'nope'), isNotNull);
      expect(outside.existsSync(), isFalse);
    });

    test('refuses to create a file that is not there', () {
      // This is a Save button on a file someone opened. A typo in a path
      // should not silently produce a new file somewhere they are not looking.
      expect(
          browser.write('${root.path}/nothing-here.txt', 'x'), 'No such file');
      expect(File('${root.path}/nothing-here.txt').existsSync(), isFalse);
    });

    test('an empty edit is a legitimate save, not a no-op', () {
      // Clearing a file is a thing people mean to do.
      File('${root.path}/notes.txt').writeAsStringSync('delete me');
      expect(browser.write('${root.path}/notes.txt', ''), isNull);
      expect(File('${root.path}/notes.txt').readAsStringSync(), isEmpty);
    });

    test('round-trips through read', () {
      File('${root.path}/a.txt').writeAsStringSync('one');
      browser.write('${root.path}/a.txt', 'two');
      expect(browser.read('${root.path}/a.txt').text, 'two');
    });

    test('keeps unicode intact', () {
      // The file tools write UTF-8; a save that mangled it would be silent
      // until someone opened the file somewhere else.
      File('${root.path}/u.txt').writeAsStringSync('x');
      browser.write('${root.path}/u.txt', 'héllo — 世界');
      expect(browser.read('${root.path}/u.txt').text, 'héllo — 世界');
    });
  });
}
