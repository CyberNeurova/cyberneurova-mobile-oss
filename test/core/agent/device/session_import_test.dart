import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/session_import.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

void main() {
  late Directory root;
  late Directory outside;
  late ShellSession session;

  setUp(() {
    root = Directory.systemTemp.createTempSync('import_session');
    outside = Directory.systemTemp.createTempSync('import_source');
    session = ShellSession(rootDir: root.path);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  File src(String name, [String body = 'hello']) =>
      File(p.join(outside.path, name))..writeAsStringSync(body);

  test('a picked file lands where the shell can reach it', () async {
    final f = src('notes.txt', 'from the picker');

    final result = await SessionImport.copyInto(session, [f.path]);

    expect(result.isOk, isTrue);
    final imported = result.files.single;
    expect(imported.name, 'notes.txt');
    expect(File(p.join(root.path, 'notes.txt')).readAsStringSync(),
        'from the picker');
    // The path handed back must be the one the shell would use, because it
    // goes straight into the message the agent reads.
    expect(imported.guestPath, contains('notes.txt'));
    expect(imported.bytes, greaterThan(0));
  });

  test('two files with the same name do not eat each other', () async {
    // Two photos both called image.jpg is the normal case, not an edge case.
    src('image.jpg', 'first');
    await SessionImport.copyInto(session, [p.join(outside.path, 'image.jpg')]);

    File(p.join(outside.path, 'image.jpg')).writeAsStringSync('second');
    final result = await SessionImport.copyInto(
        session, [p.join(outside.path, 'image.jpg')]);

    expect(result.files.single.name, 'image-2.jpg');
    expect(File(p.join(root.path, 'image.jpg')).readAsStringSync(), 'first');
    expect(File(p.join(root.path, 'image-2.jpg')).readAsStringSync(), 'second');
  });

  test('names the shell would choke on are made safe', () {
    // A slash would write outside the directory entirely. Asserted as
    // properties rather than a literal, because what matters is that no
    // separator and no leading dot survive — not the exact cosmetics.
    final traversal = SessionImport.safeName('../../etc/passwd');
    expect(traversal, isNot(contains('/')));
    expect(traversal, isNot(contains(r'\')));
    expect(traversal.startsWith('.'), isFalse);
    expect(traversal, contains('passwd'));
    // A leading dash is read as a flag by half the tools about to touch it.
    expect(SessionImport.safeName('-rf'), 'rf');
    // A leading dot hides the file, which reads as the import having failed.
    expect(SessionImport.safeName('.hidden'), 'hidden');
    expect(SessionImport.safeName('   '), 'imported');
    expect(SessionImport.safeName('ordinary name.png'), 'ordinary name.png');
  });

  test('a very long name keeps its extension', () {
    final long = '${'a' * 400}.tar.gz';
    final safe = SessionImport.safeName(long);
    expect(safe.length, lessThanOrEqualTo(120));
    expect(safe, endsWith('.gz'));
  });

  test('a file too large to be sensible is refused with the size', () async {
    // Better than filling the phone and failing later with no explanation.
    final big = src('huge.bin', 'x');
    final raf = big.openSync(mode: FileMode.write);
    raf.truncateSync(SessionImport.maxBytes + 1);
    raf.closeSync();

    final result = await SessionImport.copyInto(session, [big.path]);
    expect(result.isOk, isFalse);
    expect(result.error, contains('MB'));
    expect(result.error, contains('huge.bin'));
  });

  test('importing outside the session is refused', () async {
    final f = src('x.txt');
    final result = await SessionImport.copyInto(
      session,
      [f.path],
      intoGuestDir: '${root.path}/../..',
    );
    expect(result.isOk, isFalse);
    expect(result.error, contains('outside the session'));
  });

  test('a source that vanished says which one', () async {
    final result =
        await SessionImport.copyInto(session, [p.join(outside.path, 'gone')]);
    expect(result.isOk, isFalse);
    expect(result.error, contains('gone'));
  });

  test('several files at once all arrive', () async {
    final a = src('a.txt', 'A');
    final b = src('b.txt', 'B');

    final result = await SessionImport.copyInto(session, [a.path, b.path]);

    expect(result.files.length, 2);
    expect(File(p.join(root.path, 'a.txt')).readAsStringSync(), 'A');
    expect(File(p.join(root.path, 'b.txt')).readAsStringSync(), 'B');
  });
}
