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
      // Accept the host separator: package:path normalizes to '\' on Windows,
      // and resolveWithin (which now runs the host containment check) feeds the
      // normalized guest path back through here.
      toHostPath: (s) {
        final g = s.replaceAll(r'\', '/');
        return p.join(root.path, g.startsWith('/') ? g.substring(1) : g);
      },
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

  // Regression for the OSS security report (issue #2): under PRoot the file
  // tools run natively and follow HOST symlinks, so a guest-planted symlink
  // that escapes the rootfs AND the bind-mounted home must be refused — the
  // old `!_enforceContainment` short-circuit returned the un-canonicalized
  // host path and let file_read/file_write walk out to app-private data.
  group('resolveWithin confines host symlinks under PRoot (issue #2)', () {
    late Directory tmp;
    late String rootfs; // guest '/'  -> here
    late String homeHost; // guest '/root' -> here (a bind-mount OUTSIDE rootfs)
    late String appPrivate; // outside BOTH — the escape target
    late ShellSession session;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('shell_escape_test');
      rootfs = p.join(tmp.path, 'rootfs');
      homeHost = p.join(tmp.path, 'home');
      appPrivate = p.join(tmp.path, 'app-private');
      Directory(p.join(rootfs, 'etc')).createSync(recursive: true);
      File(p.join(rootfs, 'etc', 'hosts')).writeAsStringSync('127.0.0.1 localhost');
      Directory(homeHost).createSync(recursive: true);
      File(p.join(homeHost, 'notes.txt')).writeAsStringSync('mine');
      Directory(appPrivate).createSync(recursive: true);
      File(p.join(appPrivate, 'token')).writeAsStringSync('SECRET');

      // The session normalizes with package:path, which uses the HOST's
      // separator — '\' when the suite runs on Windows — so accept both.
      String toHost(String s) {
        final g = s.replaceAll(r'\', '/');
        if (g == '/root') return homeHost;
        if (g.startsWith('/root/')) {
          return p.join(homeHost, g.substring('/root/'.length));
        }
        return p.join(rootfs, g.startsWith('/') ? g.substring(1) : g);
      }

      session = ShellSession(
        rootDir: rootfs,
        homeDir: '/root',
        cwd: '/root',
        enforceContainment: false,
        toHostPath: toHost,
      );
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('legit paths in home and rootfs still resolve', () {
      final canonHome = Directory(homeHost).resolveSymbolicLinksSync();
      final canonRootfs = Directory(rootfs).resolveSymbolicLinksSync();
      expect(session.resolveWithin('/root/notes.txt'),
          p.join(canonHome, 'notes.txt'));
      expect(session.resolveWithin('/etc/hosts'),
          p.join(canonRootfs, 'etc', 'hosts'));
      // A not-yet-created file in home is still writable (nearest ancestor).
      expect(session.resolveWithin('/root/new.txt'),
          p.join(canonHome, 'new.txt'));
    });

    test('a guest symlink escaping to app-private is refused', () {
      Link link;
      try {
        link = Link(p.join(homeHost, 'escape'))
          ..createSync(p.join(appPrivate, 'token'));
      } catch (_) {
        markTestSkipped('host does not permit symlink creation');
        return;
      }
      expect(link.existsSync(), isTrue);
      // The core assertion: the escaping symlink resolves to null now.
      expect(session.resolveWithin('/root/escape'), isNull);
    });

    test('a write THROUGH an escaping symlinked directory is refused', () {
      try {
        Link(p.join(homeHost, 'escapedir')).createSync(appPrivate);
      } catch (_) {
        markTestSkipped('host does not permit symlink creation');
        return;
      }
      expect(session.resolveWithin('/root/escapedir/pwn.txt'), isNull);
      // changeDirectory into it returns a refusal message, not null (success).
      expect(session.changeDirectory('/root/escapedir'), isNotNull);
    });
  });
}
