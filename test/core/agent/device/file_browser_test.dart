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
        // GUEST '/', not the host rootfs dir. Under PRoot shell_workspace
        // passes guest paths (root is '/', home is '/root'), and
        // _hostRootsCanonical translates rootDir back to the host through
        // toHostPath. Handing it the already-host rootfs path sent it through
        // toHostPath's fallback a second time — p.join(rootfs, rootfs) — so the
        // rootfs root canonicalised to a nonexistent nested dir and a legit
        // '/etc/hosts' fell outside every root and resolved to null. The sibling
        // distro test above already uses '/'; this group was the odd one out.
        rootDir: '/',
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

  // Regression for the PRoot absolute-symlink follow-up to issue #2. A guest
  // ABSOLUTE symlink (`/var/run` -> `/run`, `/etc/mtab` -> `/proc/self/mounts`)
  // must resolve in the GUEST namespace so the browser can enter it and climb
  // back out — WITHOUT reopening the issue-#2 escape, so a symlink to
  // app-private host data OUTSIDE the rootfs+home is still refused. The old code
  // ran the target through the HOST realpath, which over-rejected the first
  // (it landed on the host's `/run`) and, before issue #2, followed the second.
  group('resolveWithin follows guest absolute symlinks under PRoot', () {
    late Directory tmp;
    late String rootfs; // guest '/'  -> here
    late String homeHost; // guest '/root' -> here (bind-mount OUTSIDE rootfs)
    late String appPrivate; // OUTSIDE both — the escape target
    late ShellSession session;
    late FileBrowser fb;
    var canSymlink = true;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('shell_guestlink_test');
      rootfs = p.join(tmp.path, 'rootfs');
      homeHost = p.join(tmp.path, 'home');
      appPrivate = p.join(tmp.path, 'app-private');

      // A real in-rootfs target the guest symlink points at.
      Directory(p.join(rootfs, 'run')).createSync(recursive: true);
      File(p.join(rootfs, 'run', 'hello')).writeAsStringSync('hi from rootfs');
      Directory(p.join(rootfs, 'var')).createSync(recursive: true);
      Directory(p.join(rootfs, 'etc')).createSync(recursive: true);
      Directory(homeHost).createSync(recursive: true);
      // The escape target lives OUTSIDE rootfs+home, exactly like app-private
      // data on the device (`/data/data/<pkg>/...`).
      Directory(appPrivate).createSync(recursive: true);
      File(p.join(appPrivate, 'token')).writeAsStringSync('SECRET');

      try {
        // `/var/run` -> `/run`: an absolute GUEST target. Host realpath resolves
        // it to the HOST's `/run` (over-rejected); guest-aware it is
        // `<rootfs>/run`.
        Link(p.join(rootfs, 'var', 'run')).createSync('/run');
        // Two shapes of the escape: a symlinked FILE (for read) and a symlinked
        // DIRECTORY (for cd / write-through), both pointing at app-private data.
        Link(p.join(rootfs, 'etc', 'evil'))
            .createSync(p.join(appPrivate, 'token'));
        Link(p.join(rootfs, 'etc', 'evildir')).createSync(appPrivate);
      } catch (_) {
        canSymlink = false;
      }

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
        rootDir: '/',
        homeDir: '/root',
        cwd: '/root',
        toHostPath: toHost,
      );
      fb = FileBrowser(session);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('an absolute guest symlink to an in-rootfs dir resolves', () {
      if (!canSymlink) {
        markTestSkipped('host does not permit symlink creation');
        return;
      }
      final canonRun =
          Directory(p.join(rootfs, 'run')).resolveSymbolicLinksSync();
      // Resolves to the RE-ROOTED target, never the host's own `/run`.
      expect(session.resolveWithin('/var/run'), canonRun);
      expect(session.resolveWithin('/var/run/hello'), p.join(canonRun, 'hello'));

      // The browser can enter it and read THROUGH it — proof the file tools open
      // the guest-re-rooted path, not the host link.
      final listed = fb.list('/var/run');
      expect(listed.ok, isTrue);
      expect([for (final e in listed.entries) e.name], contains('hello'));
      final read = fb.read('/var/run/hello');
      expect(read.ok, isTrue);
      expect(read.text, 'hi from rootfs');

      // ...and you can climb back out: the "up" row survives, and cd succeeds.
      expect(fb.parentOf('/var/run'), isNotNull);
      expect(session.changeDirectory('/var/run'), isNull);
    });

    test('a guest symlink to app-private host data is still refused', () {
      if (!canSymlink) {
        markTestSkipped('host does not permit symlink creation');
        return;
      }
      // The core issue-#2 assertion, preserved: the escape resolves to null.
      expect(session.resolveWithin('/etc/evil'), isNull);
      // A write THROUGH an escaping symlinked directory is refused too.
      expect(session.resolveWithin('/etc/evildir/pwn.txt'), isNull);

      // And nothing reads the secret out of it — the browser reports the
      // containment refusal rather than the app-private bytes.
      final read = fb.read('/etc/evil');
      expect(read.ok, isFalse);
      expect(read.error, contains('Outside'));
      expect(read.text, isNot(contains('SECRET')));

      // cd into the escaping directory is refused (a message, not null).
      expect(session.changeDirectory('/etc/evildir'), isNotNull);
    });
  });
}
