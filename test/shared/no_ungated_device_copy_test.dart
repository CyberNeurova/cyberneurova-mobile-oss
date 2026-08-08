import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Copy that assumes a shell must be behind a check for one.
///
/// The device features are Android-only — a PTY inside a PRoot'd rootfs needs
/// the app to execute a binary it unpacked, which iOS permits no app to do.
/// The machine-level code has always known that. The SENTENCES did not, and
/// they are what the user acts on:
///
///  * "Run a model on this phone… start one inside your Linux session" — there
///    is no session to start one in.
///  * "…so they will not show up in your shell" — there is no shell.
///  * a Google sign-in failure explained entirely in terms of Android signing
///    certificates, SHA-1s and Play app-signing keys, shown on a screen every
///    iOS user reaches.
///
/// Each was an instruction to a dead end, which is worse than saying nothing.
/// This flags the next one at test time rather than in a store review.
///
/// Scope: files NOT already gated. A file that consults `PlatformFlags` is
/// assumed to have made its choice deliberately — this is a prompt to think
/// about it once, not a ban on the words.
void main() {
  /// Phrases that only make sense where the app can run a shell.
  final deviceClaims = RegExp(
    r'(in your shell'
    r'|your Linux session'
    r'|inside your distro'
    r'|Android OAuth client'
    r'|wireless debugging)',
    caseSensitive: false,
  );

  /// Files exempt because the whole screen is already unreachable without a
  /// shell — the route redirects, so their copy cannot be shown to anyone who
  /// lacks one. Listed explicitly so adding a screen to this set is a
  /// decision someone makes on purpose.
  const behindARouteGate = {
    'adb_pairing_screen.dart', // route: adb-pairing
    'paired_history.dart', // only rendered by adb_pairing_screen
    'shell_sessions_screen.dart', // route: shell
    'shell_session_screen.dart', // route: shell-session
    'file_browser_drawer.dart', // lives inside a shell session
    'agent_environment_screen.dart', // sections gated in-place
  };

  test('the detector catches the sentences that shipped', () {
    for (final shipped in [
      'Nothing running on this phone yet. Start one inside your Linux session,',
      'not show up in your shell. Running the work on your own device',
      'This build needs an Android OAuth client for package',
    ]) {
      expect(deviceClaims.hasMatch(shipped), isTrue, reason: shipped);
    }
    // And leaves ordinary copy alone.
    expect(deviceClaims.hasMatch('Runs commands on this phone'), isFalse,
        reason: 'a capability LIST is gated by the surface, not by wording');
  });

  test('no ungated file promises something only a shell can do', () {
    final offenders = <String>[];

    for (final dir in ['lib/features', 'lib/shared']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;

      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final name = file.path.split(RegExp(r'[\\/]')).last;
        if (behindARouteGate.contains(name)) continue;

        final src = file.readAsStringSync();
        // Already asks the question — trust it.
        if (src.contains('PlatformFlags')) continue;

        final lines = src.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i].trim();
          if (l.startsWith('//') || l.startsWith('///')) continue;
          if (deviceClaims.hasMatch(l)) {
            offenders.add('${file.path}:${i + 1}  ${l.substring(
              0,
              l.length > 80 ? 80 : l.length,
            )}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'This copy promises a shell. Either gate it on '
          'PlatformFlags.hasDeviceShell with wording that is true elsewhere, '
          'or put the screen behind a route that already requires one:\n'
          '${offenders.join('\n')}',
    );
  });
}
