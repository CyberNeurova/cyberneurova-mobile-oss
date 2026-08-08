import 'package:cyberneurova_mobile/core/agent/device/linux/privileged_shell.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/root_access.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule that matters: a rooted device is never sent through ADB pairing.
/// Doing so would cost the user a setup flow to obtain strictly less than they
/// already have, since su is a superset of uid 2000.
void main() {
  const granted = RootAccess(status: RootStatus.granted, suPath: '/sbin/su');
  const present = RootAccess(status: RootStatus.present, suPath: '/sbin/su');
  const none = RootAccess(status: RootStatus.unavailable);

  test('granted root never needs ADB pairing', () {
    for (final c in PrivilegeChannel.values) {
      expect(
        PrivilegedShell.needsAdbPairing(c, granted),
        isFalse,
        reason: '$c',
      );
    }
  });

  test('su present but not granted is not enough to skip pairing', () {
    // Presence is not access — Magisk may refuse. Treating it as root would
    // strand the user with no working channel at all.
    expect(PrivilegedShell.needsAdbPairing(PrivilegeChannel.none, present),
        isTrue);
  });

  test('an already-connected ADB channel does not ask to pair again', () {
    expect(
      PrivilegedShell.needsAdbPairing(PrivilegeChannel.adb, none),
      isFalse,
    );
  });

  test('no root and no channel means pairing is worth offering', () {
    expect(PrivilegedShell.needsAdbPairing(PrivilegeChannel.none, none), isTrue);
    expect(
      PrivilegedShell.needsAdbPairing(PrivilegeChannel.shizuku, none),
      isTrue,
      reason: 'Shizuku works, but our own pairing is still worth offering',
    );
  });

  test('channel order runs most-capable first', () {
    // best() relies on this ordering; only root carries kernel capabilities.
    expect(PrivilegeChannel.values.first, PrivilegeChannel.root);
    expect(PrivilegeChannel.values.last, PrivilegeChannel.none);
  });
}
