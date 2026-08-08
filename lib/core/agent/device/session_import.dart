import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// One file brought into a session.
class ImportedFile {
  const ImportedFile({
    required this.name,
    required this.guestPath,
    required this.bytes,
  });

  final String name;

  /// Where the shell can reach it — what `cat` or the agent would take.
  final String guestPath;

  final int bytes;
}

/// The result of an import, or why it did not happen.
class ImportResult {
  const ImportResult.ok(this.files) : error = null;
  const ImportResult.failed(this.error) : files = const [];

  final List<ImportedFile> files;
  final String? error;

  bool get isOk => error == null;
}

/// Copies files from the phone into a shell session's directory.
///
/// ## Why "attach" means something different here
///
/// Attaching a file to an ordinary chat uploads it to our servers so a model
/// can read it. In a Console or Code session that is the wrong shape: the work
/// happens on the device, and what the user actually wants is the file *in
/// their working directory*, where the shell can open it, a build can consume
/// it, and the agent can read it with the file tools it already has.
///
/// It is also the only way in. Android's picker can reach the user's photos and
/// downloads; nothing else can put a byte inside this app's sandbox, so without
/// this a session can only ever work with files it produced itself.
///
/// ## Names are made safe, never silently overwritten
///
/// A picked file arrives with whatever name the source gave it — spaces,
/// slashes, non-ASCII, or a name already taken. Overwriting someone's work
/// because two photos are both called `image.jpg` is not acceptable, so
/// collisions get a numeric suffix and the original name is preserved
/// otherwise.
class SessionImport {
  const SessionImport._();

  /// Anything larger is refused rather than silently filling the phone.
  ///
  /// Generous enough for a photo, a PDF or a small archive; small enough that
  /// a mistaken pick of a 4 GB video says so instead of stalling.
  static const int maxBytes = 256 * 1024 * 1024;

  /// Copies [sourcePaths] into [session]'s current directory.
  ///
  /// Never throws — a failed import is an ordinary outcome that the UI has to
  /// render either way.
  static Future<ImportResult> copyInto(
    ShellSession session,
    List<String> sourcePaths, {
    String? intoGuestDir,
  }) async {
    if (sourcePaths.isEmpty) {
      return const ImportResult.failed('Nothing to import.');
    }

    final targetGuestDir = intoGuestDir ?? session.cwd;
    final targetHostDir = session.resolveWithin(targetGuestDir);
    if (targetHostDir == null) {
      return const ImportResult.failed(
        'That directory is outside the session.',
      );
    }

    final dir = Directory(targetHostDir);
    if (!dir.existsSync()) {
      return const ImportResult.failed('That directory does not exist.');
    }

    final imported = <ImportedFile>[];
    for (final source in sourcePaths) {
      final file = File(source);
      if (!file.existsSync()) {
        return ImportResult.failed('Could not read ${p.basename(source)}.');
      }

      final length = file.lengthSync();
      if (length > maxBytes) {
        return ImportResult.failed(
          '${p.basename(source)} is '
          '${(length / (1024 * 1024)).toStringAsFixed(0)} MB. The limit is '
          '${maxBytes ~/ (1024 * 1024)} MB.',
        );
      }

      final name = uniqueNameIn(targetHostDir, safeName(p.basename(source)));
      try {
        await file.copy(p.join(targetHostDir, name));
      } on FileSystemException catch (e) {
        return ImportResult.failed('Could not copy $name: ${e.message}');
      }

      imported.add(ImportedFile(
        name: name,
        guestPath: p.posix.join(targetGuestDir, name),
        bytes: length,
      ));
    }

    return ImportResult.ok(imported);
  }

  /// Strips what a shell would find hostile in a filename.
  ///
  /// Not cosmetic: a name containing `/` would write outside the directory,
  /// and one starting with `-` is read as a flag by half the tools the user is
  /// about to run on it.
  static String safeName(String raw) {
    var name = raw.trim().replaceAll(RegExp(r'[/\\\x00]'), '_');
    // Leading dots would hide the file the user just imported, which reads as
    // the import having failed.
    while (name.startsWith('.') || name.startsWith('-')) {
      name = name.substring(1);
    }
    if (name.isEmpty) name = 'imported';
    // Long names are legal and miserable in a 40-column terminal.
    if (name.length > 120) {
      final ext = p.extension(name);
      name = name.substring(0, 120 - ext.length) + ext;
    }
    return name;
  }

  /// `photo.jpg` → `photo-2.jpg` when taken.
  ///
  /// Suffix before the extension, so the file still opens with the right tool.
  static String uniqueNameIn(String hostDir, String name) {
    if (!File(p.join(hostDir, name)).existsSync() &&
        !Directory(p.join(hostDir, name)).existsSync()) {
      return name;
    }
    final ext = p.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    for (var i = 2; i < 1000; i++) {
      final candidate = '$stem-$i$ext';
      if (!File(p.join(hostDir, candidate)).existsSync()) return candidate;
    }
    return '$stem-${DateTime.now().microsecondsSinceEpoch}$ext';
  }
}
