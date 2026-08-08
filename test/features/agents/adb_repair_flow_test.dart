import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/screens/adb_pairing_screen.dart';

/// When the pairing key is revoked, the screen must lead with RE-PAIRING, not
/// Connect.
///
/// Reported: "the app doesn't say the key was revoked… I kept failing to
/// connect a new key." Two causes. The first is fixed already — a refused
/// connect explains itself. The second is this: `isPaired()` only checks the
/// key FILE exists, so after the device revokes its trust the screen still
/// thinks it is a normal already-paired device and leads with a big Connect
/// button. Connect fails the same way every time until the user pairs again,
/// so leading with it is the trap. On a refused connect the screen now drops
/// that button and puts the pair-again flow first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai.cyberneurova.app/device_runtime');

  /// Paired (key on disk), wireless debugging ON, but the connect is REFUSED —
  /// the revoked-key state. adbd rejects the untrusted key; the bridge reports
  /// that as needsPairing.
  void stubRevokedKey() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'adbIsPaired':
          return true;
        case 'adbConnectionInfo':
          return <String, dynamic>{'connected': false};
        case 'adbWirelessEnabled':
          return true;
        case 'adbConnect':
          return <String, dynamic>{
            'ok': false,
            'needsPairing': true,
            'error': 'Not paired with this device yet.',
          };
        default:
          return null;
      }
    });
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdbPairingScreen())),
    );
    await tester.pumpAndSettle();
  }

  Finder primaryConnect() => find.widgetWithText(FilledButton, 'Connect');
  Finder repairFlow() => find.text('Pair from the notification');

  testWidgets('a paired device leads with Connect before any refusal',
      (tester) async {
    stubRevokedKey();
    await pump(tester);
    // Before we learn the key is refused, this looks like a normal
    // reconnect-after-reboot: Connect is the primary control.
    expect(primaryConnect(), findsOneWidget);
    expect(find.text('Pair again to fix this'), findsNothing);
  });

  testWidgets('a refused connect flips the screen to re-pair', (tester) async {
    stubRevokedKey();
    await pump(tester);

    await tester.tap(primaryConnect());
    await tester.pumpAndSettle();

    // The trap is gone: no primary Connect button to keep failing on.
    expect(primaryConnect(), findsNothing,
        reason: 'leading with Connect is what made re-pairing impossible');
    // And the fix is led with, plainly.
    expect(find.text('Pair again to fix this'), findsOneWidget);
    expect(find.textContaining('stored key was refused'), findsOneWidget);
    // The reliable re-pair path is reachable below (a lazy ListView only
    // builds it once scrolled into view).
    await tester.scrollUntilVisible(repairFlow(), 400);
    expect(repairFlow(), findsOneWidget);
  });
}
