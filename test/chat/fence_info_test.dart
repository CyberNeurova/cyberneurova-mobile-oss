import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/fence_info.dart';

/// The fence regex the bubble uses. Kept in step with `_RichBody._fenceRe`;
/// the point of these tests is that a fence carrying a file name still MATCHES
/// — the old pattern rejected a dot or a colon in the info string, so
/// ```html:clock.html did not match at all and rendered as raw text.
final fenceRe = RegExp(r'```([^\n`]*)\n([\s\S]*?)```');

void main() {
  group('fence matching', () {
    test('a bare language fence still matches', () {
      final m = fenceRe.firstMatch('```dart\nvoid main() {}\n```');
      expect(m, isNotNull);
      expect(m!.group(1), 'dart');
      expect(m.group(2), 'void main() {}\n');
    });

    test('a fence naming its file matches', () {
      final m = fenceRe.firstMatch('```html:clock.html\n<h1>hi</h1>\n```');
      expect(m, isNotNull, reason: 'this is the case that used to not match');
      expect(m!.group(1), 'html:clock.html');
    });

    test('an unlabelled fence matches', () {
      final m = fenceRe.firstMatch('```\nplain\n```');
      expect(m, isNotNull);
      expect(m!.group(1), '');
    });
  });

  group('FenceInfo.parse', () {
    test('bare language', () {
      final info = FenceInfo.parse('dart');
      expect(info.language, 'dart');
      expect(info.filename, isNull);
    });

    test('language and file name', () {
      final info = FenceInfo.parse('html:clock.html');
      expect(info.language, 'html');
      expect(info.filename, 'clock.html');
    });

    test('title= form', () {
      final info = FenceInfo.parse('py title=scan.py');
      expect(info.language, 'py');
      expect(info.filename, 'scan.py');
    });

    test('a path keeps only the leaf, so a reply cannot pick a directory', () {
      final info = FenceInfo.parse('js src/app.js');
      expect(info.filename, 'app.js');
    });

    test('a bare file name names the file and implies the language', () {
      final info = FenceInfo.parse('clock.html');
      expect(info.filename, 'clock.html');
      expect(info.language, 'html');
    });

    test('comment markers are not mistaken for the language', () {
      final info = FenceInfo.parse('js // app.js');
      expect(info.language, 'js');
      expect(info.filename, 'app.js');
    });

    test('empty info string yields nothing', () {
      final info = FenceInfo.parse('');
      expect(info.language, isNull);
      expect(info.filename, isNull);
    });

    test('a version-looking token is not a file name', () {
      // `python3.11` has a dot but is a language, not something to save as.
      final info = FenceInfo.parse('python3.11');
      expect(info.filename, isNull);
      expect(info.language, 'python3.11');
    });
  });

  group('extensionForLanguage', () {
    test('maps aliases to real extensions', () {
      expect(extensionForLanguage('javascript'), 'js');
      expect(extensionForLanguage('py'), 'py');
      expect(extensionForLanguage('shell'), 'sh');
      expect(extensionForLanguage('yml'), 'yaml');
    });

    test('passes through the ones that are already extensions', () {
      expect(extensionForLanguage('html'), 'html');
      expect(extensionForLanguage('dart'), 'dart');
    });

    test('falls back to txt rather than inventing one', () {
      expect(extensionForLanguage(null), 'txt');
      expect(extensionForLanguage('brainfuck'), 'txt');
    });
  });
}
