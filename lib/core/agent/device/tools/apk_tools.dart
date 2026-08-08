import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/apk_install.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// Installs an APK the agent produced or downloaded.
///
/// ## The point
///
/// A phone that can write code and cannot run it is a text editor. This is the
/// step that closes the loop: the agent builds or fetches an APK into the
/// session directory, and it ends up installed on the same device.
///
/// ## The user is always asked
///
/// Deliberately. This goes through Android's PackageInstaller, which draws its
/// own confirmation dialog that we cannot skip, style or pre-answer — so an
/// agent cannot put software on someone's phone without them seeing what it
/// is. On a rooted device `pm install` could do it silently; that is not worth
/// the trade, and nothing here reaches for it.
///
/// A declined install is reported as a DECISION, not a failure, because an
/// agent that reads "the user said no" as "try again" turns a refusal into
/// nagging.
class ApkInstallTool implements DeviceTool {
  ApkInstallTool({required this.session});

  final ShellSession session;

  @override
  String get name => 'apk_install';

  @override
  Set<DeviceCapability> get requires => {
        DeviceCapability.installPackages,
        // The file has to be inside the session for us to read it at all.
        DeviceCapability.fileSandbox,
      };

  /// Not a network target — the scope check is about packets, and this sends
  /// none. Containment is the session directory instead.
  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final raw = (args['path'] as String?)?.trim() ?? '';
    if (raw.isEmpty) {
      return const DeviceToolResult.failure('path is required');
    }

    // Same containment check as `cd` and the file tools. Installing from an
    // arbitrary absolute path would be a way to reach outside the session
    // that none of the other tools allow.
    final host = session.resolveWithin(raw);
    if (host == null) {
      return DeviceToolResult.failure(
        'Refused: $raw is outside the session directory.',
      );
    }

    final file = File(host);
    if (!file.existsSync()) {
      return DeviceToolResult.failure('No such file: $raw');
    }
    if (p.extension(host).toLowerCase() != '.apk') {
      return const DeviceToolResult.failure(
        'That is not an APK. Android will only install a .apk, and handing it '
        'anything else fails with a message nobody can act on.',
      );
    }

    if (!await ApkInstall.isAllowed()) {
      return const DeviceToolResult.failure(
        'This app has not been allowed to install apps yet. The user has to '
        'turn it on in Settings › Apps › CyberNeurova › Install unknown apps. '
        'Ask them to, then try again — this is not something I can enable.',
      );
    }

    final size = file.lengthSync();
    context.onProgress(
      'Asking to install ${p.basename(host)} '
      '(${(size / (1024 * 1024)).toStringAsFixed(1)} MB)',
    );
    context.onProgress('Waiting for the user to confirm…');

    final result = await ApkInstall.install(host);

    return switch (result.outcome) {
      InstallOutcome.success => DeviceToolResult(
          ok: true,
          summary: 'Installed ${p.basename(host)}',
          output: 'Installed. It is on the device now.',
        ),
      // Not a failure to retry. Say what happened and stop.
      InstallOutcome.declined => const DeviceToolResult.failure(
          'The user declined the install. Do not ask again unless they bring '
          'it up — they have seen what it was and said no.',
        ),
      InstallOutcome.notPermitted => DeviceToolResult.failure(
          result.message ?? 'Not allowed to install apps on this device.',
        ),
      InstallOutcome.refused => DeviceToolResult.failure(
          'Android refused the package: ${result.message ?? "no reason given"}. '
          'Usually an unsigned build, a downgrade, or the wrong ABI.',
        ),
      InstallOutcome.failed => DeviceToolResult.failure(
          result.message ?? 'The install failed.',
        ),
    };
  }
}
