import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/apk_install.dart';
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/apk_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('install outcomes', () {
    test('a refusal by the user is a decision, not a failure to retry', () {
      // STATUS_FAILURE_ABORTED. The distinction is the whole point: an agent
      // that reads "the user said no" as a transient error asks again, and a
      // refusal becomes nagging.
      expect(ApkInstall.outcomeFor(3), InstallOutcome.declined);
    });

    test('the system rejecting the package is distinguishable from a crash',
        () {
      expect(ApkInstall.outcomeFor(0), InstallOutcome.success);
      expect(ApkInstall.outcomeFor(2), InstallOutcome.refused); // BLOCKED
      expect(ApkInstall.outcomeFor(4), InstallOutcome.refused); // INVALID
      expect(ApkInstall.outcomeFor(5), InstallOutcome.refused); // CONFLICT
      expect(ApkInstall.outcomeFor(7), InstallOutcome.refused); // INCOMPATIBLE
      expect(ApkInstall.outcomeFor(6), InstallOutcome.failed); // STORAGE
      expect(ApkInstall.outcomeFor(null), InstallOutcome.failed);
      expect(ApkInstall.outcomeFor(99), InstallOutcome.failed);
    });
  });

  group('ApkInstallTool', () {
    late Directory root;
    late ApkInstallTool tool;

    DeviceToolContext ctx() => DeviceToolContext(
          capabilities: const DeviceCapabilities(
            platform: 'android',
            osVersion: '16',
            present: {DeviceCapability.installPackages},
          ),
          scope: const AuthorizedScope.empty(),
          localSubnetCidrs: const [],
          onProgress: (_) {},
          isCancelled: () => false,
        );

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      root = Directory.systemTemp.createTempSync('apk_test');
      tool = ApkInstallTool(session: ShellSession(rootDir: root.path));
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      root.deleteSync(recursive: true);
    });

    test('refuses a path outside the session', () async {
      final r = await tool.run({'path': '${root.path}/../../etc/evil.apk'}, ctx());
      expect(r.ok, isFalse);
      expect(r.error, contains('outside the session directory'));
    });

    test('refuses something that is not an APK', () async {
      // Checked before we hand it to Android, which would fail with a message
      // nobody can act on.
      final f = File(p.join(root.path, 'notes.txt'))..writeAsStringSync('hi');
      final r = await tool.run({'path': f.path}, ctx());
      expect(r.ok, isFalse);
      expect(r.error, contains('not an APK'));
    });

    test('says so when the file is not there', () async {
      final r = await tool.run({'path': p.join(root.path, 'gone.apk')}, ctx());
      expect(r.ok, isFalse);
      expect(r.error, contains('No such file'));
    });

    test('a missing path is a usage error, not a crash', () async {
      final r = await tool.run(const {}, ctx());
      expect(r.ok, isFalse);
      expect(r.error, contains('path is required'));
    });

    test('explains the permission in terms the user can act on', () async {
      // No platform side in a test, so isAllowed() is false — which is the
      // same state as a phone that has not granted "install unknown apps".
      final f = File(p.join(root.path, 'app.apk'))..writeAsBytesSync([1, 2, 3]);
      final r = await tool.run({'path': f.path}, ctx());
      expect(r.ok, isFalse);
      // Names the actual screen. "Permission denied" would be true and useless.
      expect(r.error, contains('Install unknown apps'));
    });
  });
}
