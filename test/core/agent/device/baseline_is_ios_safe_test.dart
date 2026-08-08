import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';

/// The advertised baseline is what iOS promises the model, so it must be true
/// there.
///
/// `pureDartBaseline` is the capability set every platform advertises before
/// the Android-only additions (`execBinary`, `installPackages`, `mdnsDiscovery`,
/// `rawSocket`-with-root) are layered on in `deviceCapabilitiesProvider`. On
/// iOS nothing is layered on — the baseline IS the advertisement. And the model
/// acts on it: `promptBlock` tells the model what it can do, and the executor
/// refuses, by name, anything not present. So a capability in the baseline is a
/// promise the phone has to keep on both platforms.
///
/// The trap this guards is one edit away. Move `execBinary` into the baseline —
/// or add a new native capability and forget it isn't pure Dart — and iOS
/// starts telling the model it can run a shell. The model proposes `nmap -sS`
/// or writes a build script to run, and every attempt fails one layer below a
/// promise nobody meant to make. iOS cannot execute an app-unpacked binary at
/// all (AMFI, kernel-enforced), so there is no later version where this comes
/// good; the only fix is to not claim it.
///
/// Verified by construction: the same baseline, unchanged, is what a Research
/// session advertises on iOS today — and Research's File tools are pure Dart,
/// which is why `fileSandbox` belongs and `execBinary` does not.
void main() {
  /// Capabilities reachable from pure Dart with no platform channel and no
  /// native execution — genuinely available on iOS as much as Android.
  const pureDartSafe = {
    DeviceCapability.localNetwork, // dart:io sockets reach the LAN
    DeviceCapability.tcpConnect, // unprivileged connect, both platforms
    DeviceCapability.httpClient, // HttpClient
    DeviceCapability.dnsResolve, // InternetAddress.lookup / DoH over http
    DeviceCapability.fileSandbox, // File I/O in the app container — the one
    // capability the iOS File tools actually honor
  };

  /// Everything else: a platform channel, root, or executing a binary. None of
  /// it is safe to advertise on iOS, so none of it may sit in the baseline.
  const nativeGated = {
    DeviceCapability.icmpDgram, // needs a platform channel
    DeviceCapability.mdnsDiscovery, // NsdManager / NWBrowser
    DeviceCapability.rawSocket, // never on iOS; Android only with root
    DeviceCapability.packetCapture, // VpnService / NEPacketTunnelProvider
    DeviceCapability.execBinary, // never on iOS — AMFI, kernel-enforced
    DeviceCapability.privilegedPorts, // needs native
    DeviceCapability.installPackages, // Android PackageInstaller
  };

  test('every capability is classified as pure-Dart or native-gated', () {
    // A new enum value lands in neither set, so this fails until someone
    // decides which it is — the decision that keeps the baseline honest.
    final classified = {...pureDartSafe, ...nativeGated};
    expect(
      DeviceCapability.values.toSet().difference(classified),
      isEmpty,
      reason: 'unclassified capability: decide whether it is safe to '
          'advertise on iOS before it can reach pureDartBaseline',
    );
    expect(pureDartSafe.intersection(nativeGated), isEmpty);
  });

  test('the baseline is exactly the pure-Dart-safe set', () {
    expect(DeviceCapabilities.pureDartBaseline, pureDartSafe);
  });

  test('no native capability hides in the baseline', () {
    for (final cap in nativeGated) {
      expect(
        DeviceCapabilities.pureDartBaseline.contains(cap),
        isFalse,
        reason: '$cap needs native code or root; advertising it on iOS '
            'promises the model something the phone cannot do',
      );
    }
  });

  test('fileSandbox stays in the baseline', () {
    // The counterpart to the above: removing it would un-advertise the one
    // device capability iOS genuinely has, so the File tools would be
    // registered with no capability backing them.
    expect(
      DeviceCapabilities.pureDartBaseline,
      contains(DeviceCapability.fileSandbox),
    );
  });
}
