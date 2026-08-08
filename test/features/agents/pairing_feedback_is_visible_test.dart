import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/screens/adb_pairing_screen.dart';

/// The pairing screen has to say what happened where the user is looking.
///
/// Reported as "I'm trying to click connect on android but nothing happens".
/// It was not doing nothing. It browsed mDNS for three seconds, failed
/// because wireless debugging was off, set an error — and rendered that error
/// at the very END of a long ListView, below three setup steps, a
/// notification button, two code fields and a second Connect button. The
/// button that produced the message was at the top; the message landed
/// roughly a thousand pixels below the fold.
///
/// Wireless debugging clears itself on every reboot, so that tap fails as the
/// normal case, not the rare one. A screen whose commonest outcome is
/// invisible reads as broken.
///
/// So the assertion here is not "an error was set" — that was always true. It
/// is that the text is ON SCREEN after the tap, which is the only version of
/// the behaviour a user can tell apart from nothing happening.
///
/// Restoring the old layout to check this test fails without the fix showed
/// something worse than "off screen": the finder matched ZERO widgets. A
/// ListView only builds children near the viewport, so the message was never
/// constructed at all. "Nothing happens" was closer to literal than it looked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai.cyberneurova.app/device_runtime');

  /// The state the owner's phone was actually in: paired long ago, wireless
  /// debugging switched off by a reboot, nothing to connect to.
  void stubPairedButDebuggingOff({required List<String> calls}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'adbIsPaired':
          return true;
        case 'adbConnectionInfo':
          return <String, dynamic>{
            'connected': false,
            'device': null,
            'uid': null,
          };
        case 'adbWirelessEnabled':
          return false;
        case 'adbConnect':
          return <String, dynamic>{
            'ok': false,
            'needsPairing': false,
            'error': 'Could not reach wireless debugging.',
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

  Future<void> pumpScreen(WidgetTester tester) async {
    // A real phone, not the 800x600 test default — the whole bug is about
    // what fits on a screen, so the screen size has to be the real one.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AdbPairingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed Connect says so within the viewport', (tester) async {
    final calls = <String>[];
    stubPairedButDebuggingOff(calls: calls);
    await pumpScreen(tester);

    // The top Connect — the one offered to an already-paired device, and the
    // one the owner tapped.
    final connect = find.widgetWithText(FilledButton, 'Connect');
    expect(connect, findsOneWidget, reason: 'paired + disconnected leads with Connect');

    await tester.tap(connect);
    await tester.pumpAndSettle();

    final message = find.textContaining('Wireless debugging is switched off');
    expect(message, findsOneWidget, reason: 'the failure must be stated');

    final rect = tester.getRect(message);
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      rect.top,
      lessThan(screen),
      reason: 'the message rendered ${rect.top.toStringAsFixed(0)}px down a '
          '${screen.toStringAsFixed(0)}px screen — off the fold is the same '
          'as silence',
    );
    expect(rect.bottom, greaterThan(0));
  });

  testWidgets('and does not spend ten seconds finding out', (tester) async {
    // Discovery cannot tell "the toggle is off" from "the network is slow",
    // so it browses for the full timeout before failing. The setting answers
    // instantly, so asking it first is both faster and more truthful.
    final calls = <String>[];
    stubPairedButDebuggingOff(calls: calls);
    await pumpScreen(tester);

    calls.clear();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(calls, contains('adbWirelessEnabled'));
    expect(
      calls,
      isNot(contains('adbConnect')),
      reason: 'nothing is advertising a port with the toggle off — browsing '
          'for one is ten seconds spent to learn what we already read',
    );
  });
}
