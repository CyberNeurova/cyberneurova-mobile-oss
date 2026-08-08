import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/background_runs.dart';

/// The counting is the whole feature.
///
/// Over-count and the phone holds a wake lock over nothing — the failure mode
/// that gets a background feature uninstalled. Under-count and a build dies
/// halfway through with no explanation. Neither is visible in a screenshot, so
/// it gets tested here instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <Map<Object?, Object?>>[];
  final runs = BackgroundRuns.instance;

  setUp(() async {
    // The guard is a no-op off Android by design, so the tests have to say
    // which platform they are pretending to be.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackgroundRuns.channel, (call) async {
      if (call.method == 'setActiveRuns') {
        calls.add(Map<Object?, Object?>.from(call.arguments as Map));
      }
      return true;
    });
    await runs.reset();
    calls.clear();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackgroundRuns.channel, null);
  });

  test('nothing running means nothing is protected', () {
    expect(runs.isProtecting, isFalse);
    expect(runs.runs, 0);
  });

  test('only CPU-holding work counts as a run', () async {
    final light = runs.beginRun('Answering');
    expect(runs.isProtecting, isTrue,
        reason: 'a streaming answer still needs the process to survive');
    expect(runs.runs, 0,
        reason: 'waiting on the network must not hold the CPU awake');

    final heavy = runs.beginRun('Installing', true);
    expect(runs.runs, 1);

    heavy.end();
    expect(runs.runs, 0);
    light.end();
    expect(runs.isProtecting, isFalse);
  });

  test('ending a run twice does not underflow onto another run', () {
    final a = runs.beginRun('a', true);
    final b = runs.beginRun('b', true);
    expect(runs.runs, 2);

    a.end();
    a.end();
    a.end();

    expect(runs.runs, 1, reason: 'b is still running and must stay protected');
    b.end();
    expect(runs.runs, 0);
  });

  test('an open shell keeps us resident without holding the CPU', () async {
    runs.setSessions(2);
    await runs.push();

    expect(runs.isProtecting, isTrue);
    expect(runs.runs, 0);
    expect(calls.last['sessions'], 2);
    expect(calls.last['active'], 0);
  });

  test('closing the last shell tears everything down', () async {
    runs.setSessions(1);
    await runs.push();
    calls.clear();

    runs.setSessions(0);
    await runs.push();

    expect(runs.isProtecting, isFalse);
    expect(calls.single['sessions'], 0);
    expect(calls.single['active'], 0);
  });

  test('an unchanged state costs no binder call', () async {
    runs.setSessions(1);
    await runs.push();
    calls.clear();

    await runs.push();
    await runs.push();

    expect(calls, isEmpty);
  });

  test('a burst of changes collapses into one push', () async {
    final a = runs.beginRun('a', true);
    runs.setSessions(1);
    final b = runs.beginRun('b', true);
    a.end();
    b.end();
    runs.setSessions(0);

    await runs.push();

    // The intermediate states never reached the platform side, so the user
    // never saw a notification flicker through them.
    expect(calls, isEmpty, reason: 'net effect is the state we started in');
  });

  test('the label names the work for the notification', () async {
    final guard = runs.beginRun('Installing Kali', true);
    await runs.push();
    expect(calls.last['text'], 'Installing Kali');

    guard.end();
    await runs.push();
    expect(calls.last['text'], isNull);
  });
}
