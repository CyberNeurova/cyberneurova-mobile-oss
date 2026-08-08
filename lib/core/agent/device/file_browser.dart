import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// One entry in a directory listing.
class BrowseEntry {
  const BrowseEntry({
    required this.name,
    required this.guestPath,
    required this.hostPath,
    required this.isDirectory,
    required this.isLink,
    this.size,
    this.modified,
  });

  final String name;

  /// The path as the shell sees it — what a `cd` or `cat` would take.
  final String guestPath;

  /// The path Dart can actually open. Different under PRoot, where the guest
  /// root is a directory inside our container.
  final String hostPath;

  final bool isDirectory;
  final bool isLink;
  final int? size;
  final DateTime? modified;

  /// Whether this is worth opening in the viewer at all.
  ///
  /// Extension-based rather than content-sniffing: the check happens for every
  /// row in a listing, and stat-ing plus reading a probe of each one makes
  /// scrolling a big directory visibly slow on a phone.
  bool get looksTextual {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    if (ext.isEmpty) return true; // README, Makefile, LICENSE, dotfiles
    return !_binaryExtensions.contains(ext);
  }

  static const _binaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.heic',
    '.mp3', '.mp4', '.m4a', '.wav', '.ogg', '.webm', '.mkv', '.avi',
    '.zip', '.gz', '.xz', '.bz2', '.tar', '.7z', '.rar', '.apk', '.jar',
    '.so', '.o', '.a', '.dylib', '.dll', '.exe', '.bin', '.class', '.dex',
    '.pdf', '.ttf', '.otf', '.woff', '.woff2', '.db', '.sqlite',
  };
}

/// A directory listing, or the reason there isn't one.
class BrowseResult {
  const BrowseResult({
    required this.guestPath,
    required this.entries,
    this.error,
  });

  const BrowseResult.failure(this.guestPath, this.error) : entries = const [];

  final String guestPath;
  final List<BrowseEntry> entries;
  final String? error;

  bool get ok => error == null;
}

/// The contents of one file, bounded.
class FilePreview {
  const FilePreview({
    required this.guestPath,
    required this.text,
    required this.truncated,
    required this.totalBytes,
    this.error,
  });

  const FilePreview.failure(this.guestPath, this.error)
      : text = '',
        truncated = false,
        totalBytes = 0;

  final String guestPath;
  final String text;

  /// True when [text] is only the head of the file.
  final bool truncated;
  final int totalBytes;
  final String? error;

  bool get ok => error == null;
}

/// Reading the session's filesystem, for the UI rather than the model.
///
/// ## Why this is not just the agent's file tools
///
/// [FileListTool] and friends format their answers as prose for a model: a
/// column-aligned block of text with sizes rounded to "1.2 KB". A list view
/// needs the fields, not the paragraph, and re-parsing that text back into
/// records would be absurd.
///
/// What it does share is the boundary. Every path here goes through
/// [ShellSession.resolveWithin], the same containment check `cd` and the agent
/// use — so the sidebar cannot show the user somewhere the shell would refuse
/// to take them, and the two cannot drift apart into two different ideas of
/// where the session ends.
class FileBrowser {
  const FileBrowser(this.session);

  final ShellSession session;

  /// Files bigger than this are shown as a head, not a whole.
  ///
  /// A 40 MB log opened on a phone is a frozen app and then an OOM. The head
  /// is enough to see what a file is, which is what a viewer is for.
  static const int maxPreviewBytes = 512 * 1024;

  /// Lists [guestPath], defaulting to the session's cwd.
  ///
  /// Directories first, then files, each alphabetical and case-insensitive —
  /// the order people expect from a file manager, not the order the filesystem
  /// happens to return.
  BrowseResult list([String? guestPath]) {
    final raw = (guestPath ?? session.cwd).trim();
    // Everything below works in SHELL space, so a listing's paths are the ones
    // the user could type. The host path is only ever the local detail needed
    // to actually read the bytes.
    final target = session.absolutePath(raw.isEmpty ? session.cwd : raw);
    final host = session.resolveWithin(target);
    if (host == null) {
      return BrowseResult.failure(
          target, 'Outside the session directory');
    }

    final dir = Directory(host);
    if (!dir.existsSync()) {
      return BrowseResult.failure(target, 'No such directory');
    }

    final List<FileSystemEntity> found;
    try {
      found = dir.listSync(followLinks: false);
    } on FileSystemException catch (e) {
      // Permission denied inside a guest rootfs is ordinary, not exceptional —
      // render the reason in place rather than throwing into the widget tree.
      return BrowseResult.failure(target, e.message);
    }

    final entries = <BrowseEntry>[];
    for (final e in found) {
      final name = p.basename(e.path);
      FileStat stat;
      try {
        stat = e.statSync();
      } catch (_) {
        continue; // vanished between listing and stat — skip, do not fail
      }
      final isLink = e is Link;
      // A symlink's own stat says "link"; what matters to the user is where it
      // goes, because that decides whether tapping descends or opens.
      final isDir = stat.type == FileSystemEntityType.directory ||
          (isLink && Directory(e.path).existsSync());
      entries.add(BrowseEntry(
        name: name,
        guestPath: p.join(target, name),
        hostPath: e.path,
        isDirectory: isDir,
        isLink: isLink,
        size: isDir ? null : stat.size,
        modified: stat.modified,
      ));
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return BrowseResult(guestPath: target, entries: entries);
  }

  /// Writes [text] back to [guestPath].
  ///
  /// The counterpart to [read], and it exists for the same reason: on a phone
  /// this is the only computer. If the agent writes a file and one line is
  /// wrong, the alternatives were to describe the change in prose and hope, or
  /// to open nano in a 40-column terminal. Neither is how anyone edits a file
  /// they are looking at.
  ///
  /// Goes through [ShellSession.resolveWithin], so it cannot write anywhere
  /// `cd` would refuse to go — the same boundary as reading, not a second one
  /// that could drift from it.
  ///
  /// Returns null on success, or a reason to show the user.
  String? write(String guestPath, String text) {
    final host = session.resolveWithin(guestPath);
    if (host == null) return 'Outside the session directory';

    try {
      final file = File(host);
      // Refuse to create by accident: this is a save button on a file someone
      // opened, and a typo in a path should not silently produce a new file
      // somewhere they are not looking.
      if (!file.existsSync()) return 'No such file';
      file.writeAsStringSync(text);
      return null;
    } on FileSystemException catch (e) {
      return e.osError?.message ?? e.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Reads [guestPath] as text, bounded by [maxPreviewBytes].
  FilePreview read(String guestPath) {
    final host = session.resolveWithin(guestPath);
    if (host == null) {
      return FilePreview.failure(guestPath, 'Outside the session directory');
    }

    final file = File(host);
    if (!file.existsSync()) {
      return FilePreview.failure(guestPath, 'No such file');
    }

    try {
      final total = file.lengthSync();
      final bytes = total > maxPreviewBytes
          ? file.openSync().let((h) {
              try {
                return h.readSync(maxPreviewBytes);
              } finally {
                h.closeSync();
              }
            })
          : file.readAsBytesSync();

      // allowMalformed rather than a decode failure: a file with one bad byte
      // is still worth reading, and a viewer that refuses the whole thing over
      // it is less useful than one that shows a replacement character.
      final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
      return FilePreview(
        guestPath: guestPath,
        text: text,
        truncated: total > maxPreviewBytes,
        totalBytes: total,
      );
    } on FileSystemException catch (e) {
      return FilePreview.failure(guestPath, e.message);
    }
  }

  /// The path to put on screen — the one the terminal would print.
  ///
  /// Under a distro the session root IS the guest `/`, so the guest path is
  /// already what the user reads in their prompt and needs no rewriting. On
  /// the bare Android shell the root is a long container path that would eat
  /// the whole title bar, so it collapses to `~` the way a shell does.
  String display(String guestPath) {
    final abs = session.absolutePath(guestPath);
    if (session.rootDir == '/') return abs;
    if (p.equals(abs, session.rootDir)) return '~';
    if (p.isWithin(session.rootDir, abs)) {
      return '~/${p.relative(abs, from: session.rootDir)}';
    }
    return abs;
  }

  /// The parent of [guestPath], or null at the session root.
  ///
  /// Null is what stops the "up" affordance offering to leave the sandbox —
  /// a tap that always refuses is worse than a control that is not there.
  String? parentOf(String guestPath) {
    final abs = session.absolutePath(guestPath);
    if (p.equals(abs, session.rootDir)) return null;
    final parent = p.dirname(abs);
    if (parent == abs) return null;
    return session.resolveWithin(parent) == null ? null : parent;
  }
}

/// Shortens a path from the LEFT, the way a shell prompt does.
///
/// A deep path's tail identifies it — `…/features/shell` says where you are,
/// `/data/data/ai.cyberneurova…` says nothing. Flutter's ellipsis only trims
/// the right, and the usual trick of rendering the text right-to-left to move
/// it also relocates the leading separator: `/root` came out as `root/`.
///
/// So the trimming happens here, on the string, in whole path components.
String shortenPath(String path, {int maxComponents = 3}) {
  final parts = p.split(path).where((s) => s.isNotEmpty && s != '/').toList();
  if (parts.length <= maxComponents) return path;
  final tail = parts.sublist(parts.length - maxComponents).join('/');
  return '…/$tail';
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
