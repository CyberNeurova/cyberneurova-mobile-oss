import 'package:cyberneurova_mobile/core/agent/device/linux/shell_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The states must stay distinguishable. Collapsing "Shizuku isn't running"
/// into "you denied us" produces instructions that send people in circles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The service is Android-only, so the platform has to look like Android or
  // every call short-circuits before reaching the channel.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  const channel = MethodChannel('ai.cyberneurova.app/device_runtime');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(Object? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (c) async => handler(c));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('each platform string maps to its own state', () async {
    for (final pair in [
      ('granted', ShellServiceStatus.granted),
      ('present', ShellServiceStatus.present),
      ('denied', ShellServiceStatus.denied),
      ('unsupported', ShellServiceStatus.unsupported),
      ('unavailable', ShellServiceStatus.unavailable),
    ]) {
      mock((_) => pair.$1);
      expect(await ShellService.status(), pair.$2, reason: pair.$1);
    }
  });

  test('an unknown string is unavailable, not a crash', () async {
    // A newer platform side could return something this build has not heard
    // of. Treat it as "no service" rather than throwing.
    mock((_) => 'something-new');
    expect(await ShellService.status(), ShellServiceStatus.unavailable);
  });

  test('a missing platform side is unavailable', () async {
    mock((_) => throw MissingPluginException());
    expect(await ShellService.status(), ShellServiceStatus.unavailable);
    expect(await ShellService.serviceUid(), -1);
    expect(await ShellService.requestPermission(), isFalse);
  });

  test('exec surfaces failure as a result, never as a throw', () async {
    mock((_) => throw PlatformException(code: 'x', message: 'boom'));
    final r = await ShellService.exec('id');
    expect(r.ok, isFalse);
    expect(r.stderr, 'boom');
  });

  test('exec passes the command and timeout through', () async {
    late MethodCall seen;
    mock((c) {
      seen = c;
      return {'ok': true, 'exitCode': 0, 'stdout': 'uid=2000', 'stderr': ''};
    });
    final r = await ShellService.exec(
      'id',
      timeout: const Duration(seconds: 5),
    );
    expect(seen.method, 'shizukuExec');
    expect((seen.arguments as Map)['command'], 'id');
    expect((seen.arguments as Map)['timeoutMs'], 5000);
    expect(r.ok, isTrue);
    expect(r.stdout, 'uid=2000');
  });

  test('a null map from the platform is a failure, not a null deref', () async {
    mock((_) => null);
    expect((await ShellService.exec('id')).ok, isFalse);
  });

  test('root-started service is distinguishable by uid', () async {
    mock((_) => 0);
    expect(await ShellService.serviceUid(), 0);
    mock((_) => 2000);
    expect(await ShellService.serviceUid(), 2000);
  });
}
