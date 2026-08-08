import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// Shared plumbing for the tools that move things around.
///
/// ## Why these exist separately from file_read/file_write
///
/// An agent could already create and read files and had no way to undo either.
/// A session that runs for an hour accumulates scratch output, half-finished
/// downloads and a `notes.txt.bak` it made itself, and the only remedy was
/// `shell_exec rm` — which is unavailable on iOS, invisible to the file tools'
/// containment check, and a blunt instrument to hand a model.
///
/// Every path goes through [ShellSession.resolveWithin], the same boundary
/// `cd` and the other file tools use.
abstract class _ManageTool implements DeviceTool {
  _ManageTool({required this.session});

  final ShellSession session;

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.fileSandbox};

  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  /// Resolves [raw] inside the session, or returns why it cannot.
  ({String? host, DeviceToolResult? refusal}) resolve(
    String? raw, {
    required String field,
  }) {
    final target = (raw ?? '').trim();
    if (target.isEmpty) {
      return (host: null, refusal: DeviceToolResult.failure('$field is required'));
    }
    final host = session.resolveWithin(target);
    if (host == null) {
      return (
        host: null,
        refusal: DeviceToolResult.failure(
            'Refused: $target is outside the session directory.'),
      );
    }
    return (host: host, refusal: null);
  }

  /// Paths are echoed back relative to the session root — an absolute
  /// container path is noise to the model and leaks the sandbox layout.
  String display(String host) {
    final rel = p.relative(host, from: session.rootDir);
    return rel == '.' ? '/' : rel;
  }

  /// Whether [host] IS the session root.
  ///
  /// Checked separately everywhere it matters: deleting or moving the root is
  /// never what was meant, and the containment check alone permits it because
  /// the root is trivially inside itself.
  bool isSessionRoot(String host) {
    try {
      return p.equals(
        Directory(host).existsSync()
            ? Directory(host).resolveSymbolicLinksSync()
            : host,
        Directory(session.rootDir).resolveSymbolicLinksSync(),
      );
    } catch (_) {
      return p.equals(host, session.rootDir);
    }
  }
}

/// Renames or moves a file or directory.
///
/// One tool rather than two: on every filesystem a rename IS a move, and
/// splitting them would mean an agent picking the wrong one for
/// `mv notes.txt archive/notes.txt`.
class FileMoveTool extends _ManageTool {
  FileMoveTool({required super.session});

  @override
  String get name => 'file_move';

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final from = resolve(args['from'] as String?, field: 'from');
    if (from.refusal != null) return from.refusal!;
    final to = resolve(args['to'] as String?, field: 'to');
    if (to.refusal != null) return to.refusal!;

    final source = from.host!;
    var dest = to.host!;

    if (isSessionRoot(source)) {
      return const DeviceToolResult.failure(
        'Refused: that is the session directory itself.',
      );
    }

    final isDir = Directory(source).existsSync();
    if (!isDir && !File(source).existsSync()) {
      return DeviceToolResult.failure('No such file: ${display(source)}');
    }

    // `mv a.txt somedir` means "into it", which is what everyone expects and
    // what an agent will assume. Without this it would silently replace the
    // directory with a file.
    if (Directory(dest).existsSync()) {
      dest = p.join(dest, p.basename(source));
    }

    final overwrite = (args['overwrite'] as bool?) ?? false;
    if (!overwrite &&
        (File(dest).existsSync() || Directory(dest).existsSync())) {
      return DeviceToolResult.failure(
        '${display(dest)} already exists. Pass overwrite: true to replace it, '
        'or choose another name.',
      );
    }

    try {
      Directory(p.dirname(dest)).createSync(recursive: true);
      if (isDir) {
        Directory(source).renameSync(dest);
      } else {
        File(source).renameSync(dest);
      }
    } on FileSystemException catch (e) {
      return DeviceToolResult.failure(
        'Could not move ${display(source)}: ${e.message}',
      );
    }

    return DeviceToolResult(
      ok: true,
      summary: '${display(source)} → ${display(dest)}',
      output: 'Moved.',
    );
  }
}

/// Deletes a file or directory.
///
/// ## The recursive guard
///
/// A non-empty directory needs `recursive: true`. Not ceremony: an agent that
/// meant to remove one stale file and names its parent by mistake would
/// otherwise take the user's work with it, and nothing here has a trash can to
/// recover from. Making the destructive case say what it is costs one argument
/// and removes the whole class of accident.
class FileDeleteTool extends _ManageTool {
  FileDeleteTool({required super.session});

  @override
  String get name => 'file_delete';

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final target = resolve(args['path'] as String?, field: 'path');
    if (target.refusal != null) return target.refusal!;
    final host = target.host!;

    if (isSessionRoot(host)) {
      return const DeviceToolResult.failure(
        'Refused: that is the session directory itself. Delete what is inside '
        'it instead.',
      );
    }

    final dir = Directory(host);
    final file = File(host);

    if (dir.existsSync()) {
      final contents = dir.listSync();
      final recursive = (args['recursive'] as bool?) ?? false;
      if (contents.isNotEmpty && !recursive) {
        return DeviceToolResult.failure(
          '${display(host)} is not empty (${contents.length} item'
          '${contents.length == 1 ? '' : 's'}). Pass recursive: true if you '
          'really mean to delete all of it — there is no undo.',
        );
      }
      try {
        dir.deleteSync(recursive: recursive);
      } on FileSystemException catch (e) {
        return DeviceToolResult.failure(
          'Could not delete ${display(host)}: ${e.message}',
        );
      }
      return DeviceToolResult(
        ok: true,
        summary: 'Deleted ${display(host)}',
        output: 'Deleted ${contents.length} item'
            '${contents.length == 1 ? '' : 's'} and the directory.',
      );
    }

    if (!file.existsSync()) {
      return DeviceToolResult.failure('No such file: ${display(host)}');
    }

    final bytes = file.lengthSync();
    try {
      file.deleteSync();
    } on FileSystemException catch (e) {
      return DeviceToolResult.failure(
        'Could not delete ${display(host)}: ${e.message}',
      );
    }
    return DeviceToolResult(
      ok: true,
      summary: 'Deleted ${display(host)}',
      output: 'Deleted $bytes bytes.',
    );
  }
}

/// Creates a directory, and any parents it needs.
///
/// Parents always: an agent asked to write `src/main/app.dart` should not have
/// to discover that two of those levels are missing, one round trip at a time.
class FileMkdirTool extends _ManageTool {
  FileMkdirTool({required super.session});

  @override
  String get name => 'file_mkdir';

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final target = resolve(args['path'] as String?, field: 'path');
    if (target.refusal != null) return target.refusal!;
    final host = target.host!;

    if (File(host).existsSync()) {
      return DeviceToolResult.failure(
        '${display(host)} already exists as a file.',
      );
    }
    if (Directory(host).existsSync()) {
      // Not an error. The requested state is the actual state, and failing
      // here would make an agent branch on something it does not need to.
      return DeviceToolResult(
        ok: true,
        summary: '${display(host)} already exists',
        output: 'Nothing to do.',
      );
    }

    try {
      Directory(host).createSync(recursive: true);
    } on FileSystemException catch (e) {
      return DeviceToolResult.failure(
        'Could not create ${display(host)}: ${e.message}',
      );
    }
    return DeviceToolResult(
      ok: true,
      summary: 'Created ${display(host)}',
      output: 'Created.',
    );
  }
}
