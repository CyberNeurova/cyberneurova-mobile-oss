import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/file_browser.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

void main() {
  late Directory root;
  late FileBrowser browser;

  setUp(() {
    root = Directory.systemTemp.createTempSync('browse_test');
    Directory(p.join(root.path, 'src')).createSync();
    File(p.join(root.path, 'src', 'main.dart')).writeAsStringSync('void main(){}');
    File(p.join(root.path, 'README.md')).writeAsStringSync('# hi');
    File(p.join(root.path, 'logo.png')).writeAsBytesSync([0x89, 0x50]);
    browser = FileBrowser(ShellSession(rootDir: root.path));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('directories sort above files, each alphabetical', () {
    final r = browser.list(root.path);
    expect(r.ok, isTrue);
    expect([for (final e in r.entries) e.name],
        ['src', 'logo.png', 'README.md']);
    expect(r.entries.first.isDirectory, isTrue);
  });

  test('the sidebar cannot show what the shell would refuse to reach', () {
    // Same containment check as `cd`. If these ever diverge, the sidebar
    // becomes a way around the sandbox rather than a view into it.
    final r = browser.list('${root.path}/../..');
    expect(r.ok, isFalse);
    expect(r.error, contains('Outside'));

    final f = browser.read('/etc/passwd');
    expect(f.ok, isFalse);
  });

  test('up stops at the session root instead of offering to leave it', () {
    expect(browser.parentOf(root.path), isNull);
    expect(browser.parentOf(p.join(root.path, 'src')), isNotNull);
  });

  test('binaries are not offered to the text viewer', () {
    final r = browser.list(root.path);
    final byName = {for (final e in r.entries) e.name: e};
    expect(byName['README.md']!.looksTextual, isTrue);
    expect(byName['logo.png']!.looksTextual, isFalse);
    // Extension-less files are the ones that matter most here: README,
    // Makefile, LICENSE, dotfiles.
    expect(
      const BrowseEntry(
        name: 'Makefile',
        guestPath: '/Makefile',
        hostPath: '/Makefile',
        isDirectory: false,
        isLink: false,
      ).looksTextual,
      isTrue,
    );
  });

  test('reads a file and reports its path the way the user sees it', () {
    final f = browser.read(p.join(root.path, 'src', 'main.dart'));
    expect(f.ok, isTrue);
    expect(f.text, 'void main(){}');
    expect(f.truncated, isFalse);
    // A bare Android shell's root is a long container path, so it collapses
    // the way a shell prompt does.
    expect(browser.display(p.join(root.path, 'src')), '~/src');
    expect(browser.display(root.path), '~');
  });

  test('a huge file is shown as a head rather than freezing the app', () {
    final big = File(p.join(root.path, 'big.log'));
    big.writeAsStringSync('x' * (FileBrowser.maxPreviewBytes + 5000));

    final f = browser.read(big.path);
    expect(f.ok, isTrue);
    expect(f.truncated, isTrue);
    expect(f.text.length, lessThanOrEqualTo(FileBrowser.maxPreviewBytes));
    expect(f.totalBytes, greaterThan(FileBrowser.maxPreviewBytes));
  });

  test('under a distro the path shown is the one the terminal prints', () {
    // PRoot: the session root IS the guest '/', and the host path is a
    // directory inside our container. Showing the host answer would have the
    // sidebar say /data/data/ai.cyberneurova.app/... while the prompt two
    // inches away says /root.
    final guest = FileBrowser(ShellSession(
      rootDir: '/',
      homeDir: '/root',
      cwd: '/root',
      enforceContainment: false,
      toHostPath: (s) => p.join(root.path, s.startsWith('/') ? s.substring(1) : s),
    ));
    // Normalized rather than literal: package:path uses the HOST's separator
    // style, so these read '\root' when the suite runs on Windows and
    // '/root' on the device. The claim under test is which NAMESPACE the path
    // is in, not which slash the test machine prefers.
    expect(guest.display('/root'), p.normalize('/root'));
    expect(guest.display('.'), p.normalize('/root'));
    expect(guest.display('etc'), p.normalize('/root/etc'));

    // The load-bearing part: no host container path ever reaches the screen.
    expect(guest.display('/root'), isNot(contains(root.path)));

    expect(guest.parentOf(p.normalize('/')), isNull);
    expect(guest.parentOf('/root'), p.normalize('/'));
  });

  test('a missing directory reads as a message, not an exception', () {
    final r = browser.list(p.join(root.path, 'nope'));
    expect(r.ok, isFalse);
    expect(r.error, 'No such directory');
  });

  test('a short path is left alone; a deep one keeps its tail', () {
    // The bug this replaced: rendering right-to-left to move the ellipsis
    // also moved the leading separator, so '/root' displayed as 'root/'.
    expect(shortenPath('/root'), '/root');
    expect(shortenPath('/'), '/');
    expect(shortenPath('/a/b/c'), '/a/b/c');
    expect(shortenPath('/home/me/projects/app/lib/features/shell'),
        '…/lib/features/shell');
  });
}
