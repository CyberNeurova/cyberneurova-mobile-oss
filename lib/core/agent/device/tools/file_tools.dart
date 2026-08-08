import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/tools/line_diff.dart';

import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// Session VFS tools — `file_list`, `file_read`, `file_write`.
///
/// These are what make a multi-step run possible: the agent pipes a scan to a
/// file, reads it back on the next turn, and writes a report at the end.
/// Without them every tool result has to survive in the context window.
///
/// Pure Dart, so unlike `shell_exec` these work on **iOS too** — the phone's
/// own container is readable there even though executing binaries is not.
/// That asymmetry is the point of the typed-tool design in
/// `docs/shell/06-AGENT-INTEGRATION.md` §2: typed tools degrade across
/// platforms, the shell escape hatch does not.
///
/// Every path goes through [ShellSession.resolveWithin], so the file tools and
/// `cd` share one sandbox boundary instead of each inventing their own.
abstract class _SessionFileTool implements DeviceTool {
  _SessionFileTool({required this.session});

  final ShellSession session;

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.fileSandbox};

  /// No network target — scope is about packets, not paths. Containment is
  /// enforced by the session root instead.
  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  /// Resolves a caller-supplied path or returns the refusal result.
  ({String? path, DeviceToolResult? refusal}) resolve(String? raw) {
    final target = (raw ?? '').trim();
    if (target.isEmpty) {
      return (path: null, refusal: const DeviceToolResult.failure('path is required'));
    }
    final resolved = session.resolveWithin(target);
    if (resolved == null) {
      return (
        path: null,
        refusal: DeviceToolResult.failure(
            'Refused: $target is outside the session directory'),
      );
    }
    return (path: resolved, refusal: null);
  }

  /// Paths are echoed back relative to the session root — absolute container
  /// paths are noise to the model and leak the sandbox layout.
  String display(String absolute) {
    final rel = p.relative(absolute, from: session.rootDir);
    return rel == '.' ? '/' : rel;
  }
}

class FileListTool extends _SessionFileTool {
  FileListTool({required super.session});

  @override
  String get name => 'file_list';

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    // Default to the shared cwd, so `file_list` after a `cd` lists where the
    // user actually is.
    final r = resolve((args['path'] as String?) ?? session.cwd);
    if (r.refusal != null) return r.refusal!;
    final dir = Directory(r.path!);
    if (!dir.existsSync()) {
      return DeviceToolResult.failure('No such directory: ${display(r.path!)}');
    }

    try {
      final entries = dir.listSync(followLinks: false)..sort((a, b) => a.path.compareTo(b.path));
      if (entries.isEmpty) {
        return DeviceToolResult(
          ok: true,
          summary: '${display(r.path!)} is empty',
          output: '(empty directory)',
        );
      }

      var files = 0;
      var dirs = 0;
      final lines = <String>[];
      for (final e in entries) {
        final stat = e.statSync();
        final isDir = stat.type == FileSystemEntityType.directory;
        isDir ? dirs++ : files++;
        lines.add(
          '${isDir ? 'd' : '-'} ${_size(isDir ? null : stat.size).padLeft(9)}  '
          '${stat.modified.toIso8601String().substring(0, 16)}  '
          '${p.basename(e.path)}${isDir ? '/' : ''}',
        );
      }

      return DeviceToolResult(
        ok: true,
        summary: '${display(r.path!)} — $files file(s), $dirs dir(s)',
        output: lines.join('\n'),
      );
    } on FileSystemException catch (e) {
      return DeviceToolResult.failure('Cannot list ${display(r.path!)}: ${e.message}');
    }
  }

  static String _size(int? bytes) {
    if (bytes == null) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class FileReadTool extends _SessionFileTool {
  FileReadTool({required super.session});

  @override
  String get name => 'file_read';

  /// Same ceiling as shell_exec output. A tool that can silently drop 4 MB
  /// into the context window is a cost and truncation bug waiting to happen.
  static const int _maxChars = 16000;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final r = resolve(args['path'] as String?);
    if (r.refusal != null) return r.refusal!;
    final file = File(r.path!);
    if (!file.existsSync()) {
      return DeviceToolResult.failure('No such file: ${display(r.path!)}');
    }

    try {
      final bytes = await file.readAsBytes();
      // Lenient decode: scan output and captured payloads are frequently not
      // clean UTF-8, and losing the whole read to one bad byte is useless.
      var text = utf8.decode(bytes, allowMalformed: true);

      // Optional line window so the agent can page a large file rather than
      // being stuck with only the head.
      final offset = (args['offset_lines'] as num?)?.toInt() ?? 0;
      final limit = (args['limit_lines'] as num?)?.toInt();
      if (offset > 0 || limit != null) {
        final all = const LineSplitter().convert(text);
        final start = offset.clamp(0, all.length);
        final end = limit == null ? all.length : (start + limit).clamp(start, all.length);
        text = all.sublist(start, end).join('\n');
      }

      final truncated = text.length > _maxChars;
      if (truncated) text = '${text.substring(0, _maxChars)}\n… truncated';

      final lineCount = '\n'.allMatches(text).length + 1;
      return DeviceToolResult(
        ok: true,
        summary:
            '${display(r.path!)} — ${FileListTool._size(bytes.length)}, $lineCount line(s)'
            '${truncated ? ' (truncated)' : ''}',
        output: text,
      );
    } on FileSystemException catch (e) {
      return DeviceToolResult.failure('Cannot read ${display(r.path!)}: ${e.message}');
    }
  }
}

class FileWriteTool extends _SessionFileTool {
  FileWriteTool({required super.session});

  @override
  String get name => 'file_write';

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final r = resolve(args['path'] as String?);
    if (r.refusal != null) return r.refusal!;
    final content = (args['content'] as String?) ?? '';
    final append = args['append'] as bool? ?? false;

    try {
      final file = File(r.path!);
      // Create intermediate dirs — an agent writing scans/2026/report.md
      // shouldn't have to mkdir -p first.
      final parent = Directory(p.dirname(file.path));
      if (!parent.existsSync()) parent.createSync(recursive: true);

      // Read the old content BEFORE overwriting, so the card can show what
      // actually changed rather than "wrote 2431 chars" — which is the one
      // thing you want to know before trusting an edit. Best-effort: a binary
      // or unreadable file just means no diff, never a failed write.
      final existed = file.existsSync();
      String? previous;
      if (existed) {
        try {
          previous = await file.readAsString();
        } on FileSystemException {
          previous = null;
        } on FormatException {
          previous = null; // not UTF-8; diffing it would be meaningless
        }
      }

      await file.writeAsString(
        content,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );

      final size = await file.length();

      // Append is a diff against the old content plus what we added, not
      // against the fragment on its own.
      final after = append ? '${previous ?? ''}$content' : content;
      final diff = previous == null && existed
          ? ''
          : unifiedDiff(previous ?? '', after);

      return DeviceToolResult(
        ok: true,
        summary:
            '${append ? 'Appended' : 'Wrote'} ${content.length} chars → ${display(r.path!)} '
            '(${FileListTool._size(size)})',
        output: diff.isEmpty ? display(r.path!) : diff,
        artifacts: [
          {
            'type': 'file',
            'path': display(r.path!),
            'bytes': size,
          }
        ],
      );
    } on FileSystemException catch (e) {
      return DeviceToolResult.failure('Cannot write ${display(r.path!)}: ${e.message}');
    }
  }
}
