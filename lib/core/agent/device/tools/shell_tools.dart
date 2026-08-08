import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_backend.dart';
import 'package:cyberneurova_mobile/core/agent/device/pty_shell.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// `shell_exec` — the escape hatch, per `docs/shell/06-AGENT-INTEGRATION.md` §2.
///
/// The typed tools (`net_scan`, `http_probe`, `dns_query`) exist so the policy
/// engine has something to reason about. This one deliberately does not, so it
/// carries the stricter policy profile and the model is told to prefer a typed
/// tool when one fits.
///
/// **Android only.** It runs `/system/bin/sh -c`, which is present on every
/// Android device and gives the toybox applet set for free — no bundled
/// binaries needed for the basics. iOS never reaches here: `execBinary` is
/// absent from its capability set, so [DeviceExecutor] refuses first with a
/// named missing capability, which is what lets the agent switch technique
/// instead of retrying. AMFI code signing makes that permanent, not a gap to
/// fill later (`docs/shell/03-IOS-RUNTIME.md`).
///
/// The command runs against the shared [ShellSession], so `cd` persists into
/// the user's next typed command — the invariant from `00-OVERVIEW.md` §1.
class ShellExecTool implements DeviceTool {
  ShellExecTool({required this.session, this.onRecord, this.backend});

  final ShellSession session;

  /// Echoes the command and its output into the pane's scrollback.
  ///
  /// Without this the agent works **invisibly**: it runs `nmap`, reports a
  /// conclusion, and the terminal shows nothing — so the user cannot check the
  /// work, and the shared-history half of `00-OVERVIEW.md` §1 is true in the
  /// model and absent from the screen. Optional so the tool stays usable
  /// headlessly and in tests.
  final void Function(String command, String output, {bool ok})? onRecord;

  /// Where the command runs. Null means Android's own shell — the agent and
  /// the terminal must share this, or the agent would be operating on a
  /// different filesystem than the one the user is looking at.
  final ShellBackend? backend;

  @override
  String get name => 'shell_exec';

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.execBinary};

  /// No network target — scope enforcement doesn't apply. That is exactly why
  /// this tool gets the stricter policy profile server-side: an arbitrary
  /// command can reach the network without ever naming a host.
  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  /// Marker used to read the shell's final cwd back out. A `cd` inside
  /// `sh -c` dies with the subshell, so without this the session's working
  /// directory would silently never move and the shared-cwd invariant would
  /// be a lie.
  static const _cwdMarker = '__CN_CWD__';

  static const int _maxOutputChars = 16000;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return const DeviceToolResult.failure('command is required');
    }

    if (args['background'] == true) {
      // Honest refusal beats a fake success. Backgrounding needs the session
      // service + job table from `docs/shell/01-ANDROID-RUNTIME.md`, which
      // isn't built yet.
      return const DeviceToolResult.failure(
        'background execution is not supported yet — run with background:false, '
        'or use a shorter command',
      );
    }

    final timeout = Duration(
      seconds: (args['timeout_s'] as num?)?.toInt().clamp(1, 900) ?? 60,
    );

    // `cd` as the whole command is handled in-process: it must mutate the
    // shared session, not a throwaway subshell.
    final bare = command.replaceFirst(RegExp(r'^cd\s+'), '');
    if (RegExp(r'^cd(\s|$)').hasMatch(command) && !bare.contains(RegExp(r'[;&|]'))) {
      final err = session.changeDirectory(bare.trim());
      if (err != null) return DeviceToolResult.failure(err);
      return DeviceToolResult(
        ok: true,
        summary: 'cwd → ${session.cwd}',
        output: session.cwd,
      );
    }

    Process? process;
    final out = StringBuffer();
    var truncated = false;

    void collect(String chunk) {
      if (out.length >= _maxOutputChars) {
        truncated = true;
        return;
      }
      out.write(chunk);
      for (final line in chunk.split('\n')) {
        if (line.trim().isNotEmpty && !line.contains(_cwdMarker)) {
          context.onProgress(line);
        }
      }
    }

    try {
      // Append a pwd echo so the session cwd follows a `cd` that ran as part
      // of a compound command (`cd /tmp && ls`).
      final wrapped = '$command\n__cn_rc=\$?; printf "\\n$_cwdMarker%s" "\$(pwd)"; exit \$__cn_rc';

      final b = backend;
      process = await Process.start(
        b?.executable ?? '/system/bin/sh',
        b?.commandArgs(wrapped, workingDir: session.cwd) ?? ['-c', wrapped],
        // Under PRoot the cwd is a GUEST path that the host cannot chdir to;
        // PRoot is told it via --cwd instead.
        workingDirectory:
            (b == null || b.enforceHostContainment) ? session.cwd : null,
        // The pane's env goes on top, MINUS the host filesystem vars when
        // this runs inside a guest rootfs. `session.env` carries an Android
        // PATH — our prefix, /system/bin, /apex/… — none of which exist in
        // the distro, so letting it override the guest's PATH made every
        // command return `exit 127`: ls, bash, sh, all of them. The terminal
        // has stripped these since it hit the same wall; shell_exec never
        // did, so the agent had a shell where nothing was on PATH while the
        // user's terminal beside it worked fine.
        environment: {
          ...?b?.environment(),
          ...(b != null && !b.enforceHostContainment
              ? hostOnlyStripped(session.env)
              : session.env),
        },
        runInShell: false,
      );

      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(collect)
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(collect)
          .asFuture<void>();

      // Poll cancellation so a user tapping Stop actually kills the process
      // rather than orphaning it — a scan that ignores Stop is worse than one
      // that never started (`device_executor.dart` DeviceToolContext).
      var cancelled = false;
      final watchdog = Timer.periodic(const Duration(milliseconds: 200), (t) {
        if (context.isCancelled()) {
          cancelled = true;
          process?.kill(ProcessSignal.sigkill);
          t.cancel();
        }
      });

      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          throw TimeoutException('shell_exec');
        });
      } finally {
        watchdog.cancel();
      }
      await Future.wait([stdoutDone, stderrDone]).catchError((_) => <void>[]);

      if (cancelled) {
        return const DeviceToolResult.failure('Cancelled');
      }

      // Pull the cwd marker back out and move the shared session.
      var text = out.toString();
      final markerAt = text.lastIndexOf(_cwdMarker);
      if (markerAt >= 0) {
        final reported = text.substring(markerAt + _cwdMarker.length).trim();
        text = text.substring(0, markerAt).trimRight();
        if (reported.isNotEmpty && reported != session.cwd) {
          // Reuse changeDirectory so the same sandbox check applies — a
          // command that cd'd outside the session root must not stick.
          session.changeDirectory(reported);
        }
      }
      if (truncated) text = '$text\n… output truncated';

      final firstLine = text
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      final summary = exitCode == 0
          ? (firstLine.isEmpty
              ? 'ok (no output)'
              : (firstLine.length > 80
                  ? '${firstLine.substring(0, 80)}…'
                  : firstLine))
          : 'exit $exitCode';

      // Show the user what the agent just did, in their terminal, before
      // returning it to the model.
      onRecord?.call(command, text, ok: exitCode == 0);

      return DeviceToolResult(
        ok: exitCode == 0,
        summary: summary,
        output: text.isEmpty ? '(no output)' : text,
        error: exitCode == 0 ? null : 'Command exited with status $exitCode',
      );
    } on TimeoutException {
      return DeviceToolResult.failure(
          'Timed out after ${timeout.inSeconds}s — the process was killed');
    } on ProcessException catch (e) {
      return DeviceToolResult.failure('Could not run the shell: ${e.message}');
    } catch (e) {
      return DeviceToolResult.failure('shell_exec failed: $e');
    }
  }
}
