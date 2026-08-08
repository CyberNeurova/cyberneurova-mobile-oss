import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';

/// A surface may only be offered where it can keep its own promises.
///
/// Console and Code describe themselves, in the copy shown to the user, as
/// running commands on this phone and writing real files here. Both need a PTY
/// inside a PRoot'd rootfs, which requires executing a binary the app unpacked
/// — something iOS does not permit any app to do. That is a platform boundary,
/// not a backlog item, so the honest handling is to not offer them at all
/// rather than let them fail one layer below a screen that already promised.
///
/// Before this, nothing in the UI asked. Eight `Platform.isAndroid` checks in
/// `core/agent/device` each stopped one machine-level operation correctly and
/// invisibly, while the hub kept showing all three cards on every platform.
void main() {
  test('the surfaces that need a shell are the ones that promise one', () {
    // Read from the copy itself: if a surface tells the user it runs commands
    // or writes files on the phone, it needs the device.
    for (final s in AgentSurface.values) {
      final promisesDevice = s.userCapabilities.any((c) {
        final t = c.toLowerCase();
        return t.contains('on this phone') || t.contains('in your shell');
      });
      expect(s.needsDeviceShell, promisesDevice,
          reason: '${s.title} says: ${s.userCapabilities}');
    }
  });

  test('Console and Code need the device, Research does not', () {
    expect(AgentSurface.console.needsDeviceShell, isTrue);
    expect(AgentSurface.code.needsDeviceShell, isTrue);
    expect(AgentSurface.research.needsDeviceShell, isFalse,
        reason: 'Research reads its sources over HTTP from the user'
            ' connection — it stands on its own anywhere');
  });

  test('Research is offered on every platform', () {
    expect(AgentSurface.research.isAvailableHere, isTrue);
  });

  test('availability follows the platform flag', () {
    // The suite runs on the host, so this asserts the relationship rather
    // than a fixed answer — it holds on whichever machine runs it.
    final expected = PlatformFlags.hasDeviceShell;
    expect(AgentSurface.console.isAvailableHere, expected);
    expect(AgentSurface.code.isAvailableHere, expected);
  });

  test('hasDeviceShell means Android, and the host proves the negative', () {
    expect(PlatformFlags.hasDeviceShell, PlatformFlags.isAndroid);
    // Desktop and iOS alike: not Android, no shell surfaces. Running the suite
    // anywhere but an Android device exercises the unavailable branch, which
    // is the one that was never covered.
    if (!Platform.isAndroid) {
      expect(PlatformFlags.hasDeviceShell, isFalse);
      expect(AgentSurface.console.isAvailableHere, isFalse);
      expect(AgentSurface.research.isAvailableHere, isTrue);
    }
  });
}
