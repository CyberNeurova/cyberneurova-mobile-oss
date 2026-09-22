import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// ShellSession holds the shared-cwd invariant from `docs/shell/00-OVERVIEW.md`
/// §1 AND the sandbox boundary — a `cd` that escapes the session root would
/// let the agent wander the filesystem. Both are worth locking down.
///
/// Assertions are separator-agnostic on purpose: this runs on the dev host
/// under `flutter test` (Windows here) but ships to Android, and the sandbox
/// check has to be right on both.
void main() {
  late Directory root;
  late String canonicalRoot;
  late ShellSession session;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cn_shell_test');
    canonicalRoot = root.resolveSymbolicLinksSync();
    Directory(p.join(root.path, 'scans', 'deep')).createSync(recursive: true);
    // Build from the SYMLINK-RESOLVED root, because that is what the session
    // reports and checks against after any `cd` (changeDirectory canonicalizes;
    // _within resolves the root). Building from the raw path only agreed by
    // luck on filesystems with no symlink in the temp path — macOS symlinks
    // `/var` -> `/private/var`, so `session.cwd` came back `/var/…` while every
    // assertion here expects `/private/var/…`, and the suite went red on the
    // macOS/CI host (outbox 067). Feeding the canonical path makes the initial
    // cwd match the post-`cd` cwd on every host.
    session = ShellSession(rootDir: canonicalRoot);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('ShellSession.changeDirectory', () {
    test('starts at the root', () {
      expect(p.equals(session.cwd, canonicalRoot), isTrue);
    });

    test('moves into a relative subdirectory and persists', () {
      expect(session.changeDirectory('scans'), isNull);
      expect(p.equals(session.cwd, p.join(canonicalRoot, 'scans')), isTrue);

      // The whole point of the shared session: the next call starts here, so
      // a relative `cd` composes instead of resetting to the root.
      expect(session.changeDirectory('deep'), isNull);
      expect(
        p.equals(session.cwd, p.join(canonicalRoot, 'scans', 'deep')),
        isTrue,
      );
    });

    test('accepts an absolute path inside the root', () {
      expect(session.changeDirectory(p.join(root.path, 'scans')), isNull);
      expect(p.equals(session.cwd, p.join(canonicalRoot, 'scans')), isTrue);
    });

    test('rejects escaping the session root with ..', () {
      session.changeDirectory('scans');
      final before = session.cwd;
      final err = session.changeDirectory(p.join('..', '..', '..', '..'));
      expect(err, isNotNull, reason: 'must not be allowed above the root');
      // cwd must not move on a refusal.
      expect(session.cwd, before);
    });

    test('rejects an absolute path outside the root', () {
      final before = session.cwd;
      // Use a directory that definitely exists outside the root, so we're
      // testing the containment check rather than an existence check.
      final outside = Directory.systemTemp.path;
      final err = session.changeDirectory(outside);
      expect(err, isNotNull);
      expect(err, contains('outside the session directory'));
      expect(session.cwd, before);
    });

    test('reports a missing directory rather than moving', () {
      final before = session.cwd;
      final err = session.changeDirectory('nope');
      expect(err, contains('No such directory'));
      expect(session.cwd, before);
    });

    test('~ and empty return to the root', () {
      session.changeDirectory(p.join('scans', 'deep'));
      expect(session.changeDirectory('~'), isNull);
      expect(p.equals(session.cwd, canonicalRoot), isTrue);
    });
  });

  group('ShellSession env', () {
    test('is shared and mutable, and exposed read-only', () {
      session.setEnv('SCAN_TARGET', '192.168.1.0/24');
      expect(session.env['SCAN_TARGET'], '192.168.1.0/24');
      expect(() => session.env['X'] = 'y', throwsUnsupportedError);
    });
  });
}
