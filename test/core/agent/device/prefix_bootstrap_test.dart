import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/device/prefix_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The bootstrap is pure filesystem work, so it is testable on the host — no
/// device, no `nativeLibraryDir`, just a directory standing in for one. That
/// matters because the thing most likely to break it (an app update changing
/// the install hash and dangling every link) is tedious to reproduce on a
/// phone and trivial here.
void main() {
  late Directory tmp;
  late Directory fakeLibDir;
  late Directory prefix;

  /// Pretends to be a shipped `lib*.so`.
  void shipLibrary(String name) {
    File(p.join(fakeLibDir.path, name)).writeAsStringSync('#!/bin/sh\n');
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('prefix_bootstrap_test');
    fakeLibDir = Directory(p.join(tmp.path, 'lib', 'arm64'))
      ..createSync(recursive: true);
    prefix = Directory(p.join(tmp.path, 'shell'))..createSync(recursive: true);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  PrefixBootstrap boot({String? libDir}) => PrefixBootstrap(
        prefixDir: prefix.path,
        nativeLibraryDir: libDir ?? fakeLibDir.path,
      );

  group('availableLibraries', () {
    test('reports only what is actually on disk', () {
      shipLibrary('libbusybox.so');
      final present = boot().availableLibraries(toolset: const {
        'libbusybox.so': ['sh'],
        'libnmapcore.so': ['nmap'],
      });
      expect(present, ['libbusybox.so']);
    });

    test('is empty when nativeLibraryDir does not exist', () {
      final present = boot(libDir: p.join(tmp.path, 'nope'))
          .availableLibraries(toolset: const {
        'libbusybox.so': ['sh'],
      });
      expect(present, isEmpty);
    });
  });

  group('linkBinaries', () {
    test('one multicall binary becomes many named commands', () async {
      shipLibrary('libbusybox.so');
      final linked = await boot().linkBinaries(toolset: const {
        'libbusybox.so': ['grep', 'sed', 'awk'],
      });

      expect(linked, ['awk', 'grep', 'sed']); // sorted
      for (final applet in linked) {
        final link = Link(p.join(prefix.path, 'bin', applet));
        expect(link.existsSync(), isTrue, reason: '$applet should be linked');
        expect(link.targetSync(), p.join(fakeLibDir.path, 'libbusybox.so'));
      }
    });

    test('skips applets whose library was not shipped', () async {
      shipLibrary('libbusybox.so');
      final linked = await boot().linkBinaries(toolset: const {
        'libbusybox.so': ['grep'],
        'libnmapcore.so': ['nmap'],
      });

      expect(linked, ['grep']);
      expect(Link(p.join(prefix.path, 'bin', 'nmap')).existsSync(), isFalse);
    });

    test('is idempotent — running twice changes nothing', () async {
      shipLibrary('libbusybox.so');
      const toolset = {
        'libbusybox.so': ['grep']
      };
      final first = await boot().linkBinaries(toolset: toolset);
      final second = await boot().linkBinaries(toolset: toolset);
      expect(second, first);
      expect(Directory(p.join(prefix.path, 'bin')).listSync().length, 1);
    });

    test('re-points stale links after an app update', () async {
      shipLibrary('libbusybox.so');
      const toolset = {
        'libbusybox.so': ['grep']
      };
      await boot().linkBinaries(toolset: toolset);

      // An app update moves nativeLibraryDir — the path carries an
      // install-specific hash. Yesterday's link now dangles, and a dangling
      // link on $PATH is worse than no link: exec fails with ENOENT on a name
      // the agent was told it had.
      final newLibDir = Directory(p.join(tmp.path, 'lib2', 'arm64'))
        ..createSync(recursive: true);
      File(p.join(newLibDir.path, 'libbusybox.so')).writeAsStringSync('x');

      final linked =
          await boot(libDir: newLibDir.path).linkBinaries(toolset: toolset);

      expect(linked, ['grep']);
      expect(
        Link(p.join(prefix.path, 'bin', 'grep')).targetSync(),
        p.join(newLibDir.path, 'libbusybox.so'),
      );
    });

    test('creates bin/ when the prefix is empty', () async {
      shipLibrary('libbusybox.so');
      expect(Directory(p.join(prefix.path, 'bin')).existsSync(), isFalse);
      await boot().linkBinaries(toolset: const {
        'libbusybox.so': ['grep']
      });
      expect(Directory(p.join(prefix.path, 'bin')).existsSync(), isTrue);
    });

    test('empty default toolset links nothing but still succeeds', () async {
      expect(await boot().linkBinaries(), isEmpty);
    });
  });

  group('pathFor', () {
    // `:` is the separator on the platform this ships to, and these tests run
    // on the host — where a temp path starts `C:\`. So assert on the whole
    // string rather than splitting it, which would tear the drive letter off
    // and fail for a reason that cannot happen on a device.
    test('puts our bin first so bundled tools win over system ones', () {
      final path = boot().pathFor();
      expect(path, startsWith('${p.join(prefix.path, 'bin')}:'));
      expect(path, contains('/system/bin'));
    });

    test('keeps the inherited PATH, after ours', () {
      final path = boot().pathFor(inherited: '/vendor/bin');
      expect(
        path,
        '${p.join(prefix.path, 'bin')}:/vendor/bin:/system/bin:/system/xbin',
      );
    });

    test('de-dupes without reordering', () {
      // A shell that already has /system/bin must not end up with it twice —
      // a duplicated entry doubles every failed lookup's stat() count.
      final path = boot().pathFor(inherited: '/system/bin');
      expect(RegExp('/system/bin(?!/)').allMatches(path).length, 1);
      expect(path, startsWith('${p.join(prefix.path, 'bin')}:'));
    });

    test('ignores an empty inherited PATH', () {
      expect(boot().pathFor(inherited: ''), boot().pathFor());
    });
  });
}
