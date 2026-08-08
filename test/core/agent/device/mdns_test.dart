import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/mdns.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Mdns.channel, null);
  });

  void reply(Object? value) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Mdns.channel, (call) async {
      if (call.method != 'mdnsDiscover') return null;
      return value;
    });
  }

  test('reads what the platform found', () async {
    reply([
      {
        'name': 'Living Room TV',
        'type': '_googlecast._tcp',
        'host': '192.168.1.31',
        'port': 8009,
      },
    ]);

    final found = await Mdns.discover();
    expect(found.length, 1);
    expect(found.single.name, 'Living Room TV');
    expect(found.single.port, 8009);
    // The one-liner is what lands in the tool result, so it has to carry the
    // thing a scan cannot give you: the name.
    expect(found.single.line, contains('Living Room TV'));
    expect(found.single.line, contains('192.168.1.31:8009'));
  });

  test('one malformed entry does not cost the rest', () async {
    // Same rule the model list and the paired-device list already follow.
    reply([
      {'name': 'no host'},
      'a string',
      {'host': '10.0.0.5', 'port': 22, 'name': 'nas', 'type': '_ssh._tcp'},
      {'host': '10.0.0.6', 'port': 'not an int'},
    ]);

    final found = await Mdns.discover();
    expect([for (final s in found) s.host], ['10.0.0.5']);
  });

  test('a nameless service falls back to its address', () async {
    // A blank row is indistinguishable from a rendering bug.
    reply([
      {'name': '', 'type': '_http._tcp', 'host': '10.0.0.9', 'port': 80},
    ]);
    expect((await Mdns.discover()).single.name, '10.0.0.9');
  });

  test('a silent network is an empty list, not an error', () async {
    reply(<Object?>[]);
    expect(await Mdns.discover(), isEmpty);
  });

  test('a build with no platform side answers empty', () async {
    // MissingPluginException must not surface as a crash mid-run.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Mdns.channel, null);
    expect(await Mdns.discover(), isEmpty);
  });

  test('iOS gets nothing rather than a channel error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    reply([
      {'host': '1.2.3.4', 'port': 1, 'name': 'x', 'type': '_t._tcp'},
    ]);
    expect(await Mdns.discover(), isEmpty);
  });
}
