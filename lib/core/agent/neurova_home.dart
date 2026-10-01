import 'dart:convert';
import 'dart:io';

/// `~/.neurova` — the app's own directory inside the user's shell home.
///
/// The owner asked for this by name: *"can we have .neurova for managing
/// memory and chats in a folder they can open"*. The point is not storage —
/// the app already had storage — it is that the storage is somewhere the user
/// can reach. It sits in the shell home, so `ls -a ~` shows it and `cat
/// ~/.neurova/chats/<id>.json` works from the terminal on the phone, which is
/// the whole premise of this product: the machine is theirs, and what the
/// agent knows about them should not be locked in an app-private database they
/// cannot open.
///
/// Layout:
///
///     ~/.neurova/
///       README            what this is, for whoever finds it with ls -a
///       chats/<id>.json   one conversation, prose and all
///       memory/           notes that outlive a single session
///
/// Deliberately plain JSON, one file per chat, rewritten whole. A conversation
/// is tens of turns; a schema to migrate later costs more than rewriting a
/// small file now.
class NeurovaHome {
  NeurovaHome(this.shellHome);

  /// Host path of the shell home (`shellRootDirProvider`), NOT a guest path —
  /// this is Dart writing files, not the distro.
  final String shellHome;

  Directory get root => Directory('$shellHome/.neurova');
  Directory get chats => Directory('${root.path}/chats');
  Directory get memory => Directory('${root.path}/memory');

  static const _readme = '''
This directory belongs to CyberNeurova.

  chats/    One JSON file per conversation, including the text of every turn.
            Agent sessions are not stored on our servers, so this is the only
            copy — deleting a file here loses that conversation. A file the
            app cannot read is renamed to <id>.json.unreadable-<time> and
            left alone, never written over.
  memory/   Notes the agent keeps between sessions.

It is plain JSON on purpose. Read it, grep it, back it up, delete it. It is
your phone.
''';

  /// Creates the tree if it is not there. Safe to call repeatedly.
  Future<void> ensure() async {
    if (!await chats.exists()) await chats.create(recursive: true);
    if (!await memory.exists()) await memory.create(recursive: true);
    final readme = File('${root.path}/README');
    if (!await readme.exists()) await readme.writeAsString(_readme);
  }

  File chatFile(String chatId) {
    // A chat id is a server UUID, but this is a path — sanitise regardless.
    final safe = chatId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return File('${chats.path}/$safe.json');
  }
}

/// One stored turn. Deliberately smaller than the app's MessageModel: what is
/// worth keeping is who said what and when, not the transport details.
class StoredTurn {
  const StoredTurn({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'at': createdAt.toIso8601String(),
      };

  static StoredTurn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final role = raw['role'];
    final content = raw['content'];
    if (id is! String || role is! String || content is! String) return null;
    return StoredTurn(
      id: id,
      role: role,
      content: content,
      createdAt: _readAt(raw['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// The timestamp, read the way anything other than [toJson] might write it.
  ///
  /// This used to be `raw['at'] as String?`, and a cast that throws is not a
  /// tolerant read: one turn with an epoch number in it — a hand edit, or a
  /// tool on the phone tidying the file — threw out of the load loop and the
  /// whole conversation read as empty. A number is taken as epoch
  /// milliseconds, which is what JavaScript's `Date.now()` writes. Anything
  /// else is the caller's fallback, so a wrong timestamp costs the turn its
  /// place in the order, never its text.
  static DateTime? _readAt(Object? at) {
    if (at is String) return DateTime.tryParse(at);
    // fromMillisecondsSinceEpoch throws outside ±8.64e15, and toInt throws on
    // infinity — which is what jsonDecode makes of a literal like 1e400.
    if (at is num && at.isFinite && at.abs() <= 8.64e15) {
      return DateTime.fromMillisecondsSinceEpoch(at.toInt());
    }
    return null;
  }
}

/// Reads and writes conversations under `~/.neurova/chats`.
///
/// This exists because agent-run turns are not persisted server-side: their
/// tool cards came back after a restart and the conversation did not, so the
/// user reopened a session to a wall of actions with no words around them —
/// reported twice by the owner. Until the server stores them, the phone does.
class LocalChatStore {
  LocalChatStore(this.home);

  final NeurovaHome home;

  static const _version = 1;

  /// Chats whose file on disk could be neither read nor moved aside by the
  /// last [load]. Saving would write over it, so for those the save is
  /// skipped while that file is still in place: losing this session's new
  /// turns is the lesser harm next to destroying the copy of everything
  /// before them.
  final _blocked = <String>{};

  Future<void> save(String chatId, List<StoredTurn> turns) async {
    final file = home.chatFile(chatId);
    if (_blocked.contains(chatId)) {
      // Checked here rather than when the move failed: overlapping loads of
      // the same unreadable file race to move it, and the one whose rename
      // loses can still see the file an instant before the winner moves it.
      // What matters is whether it is in the way now.
      if (await file.exists()) return;
      _blocked.remove(chatId);
    }
    if (turns.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await home.ensure();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'v': _version,
        'chat_id': chatId,
        'saved_at': DateTime.now().toIso8601String(),
        'turns': [for (final t in turns) t.toJson()],
      }),
    );
  }

  /// Everything stored for [chatId], oldest first. Empty when there is nothing
  /// or the file cannot be read — a damaged file must degrade to "no history",
  /// never to a chat that will not open.
  ///
  /// "No history" must not become "no file", though. The chat opens empty, the
  /// next prompt saves the visible messages, and if the unreadable file were
  /// still in place that save would be written over the only copy of the
  /// conversation. So a file that cannot be read as a whole is moved aside
  /// first, and a single bad turn costs that turn rather than the file.
  Future<List<StoredTurn>> load(String chatId) async {
    _blocked.remove(chatId);
    final file = home.chatFile(chatId);
    try {
      if (!await file.exists()) return const [];
    } catch (_) {
      return const [];
    }

    final rows = await _readRows(file);
    if (rows == null) {
      await _setAside(chatId, file);
      return const [];
    }

    final out = <StoredTurn>[];
    for (final raw in rows) {
      try {
        final turn = StoredTurn.fromJson(raw);
        if (turn != null) out.add(turn);
      } catch (_) {
        // fromJson is meant not to throw; if some shape still makes it, that
        // is one turn lost, not the conversation.
      }
    }
    return out;
  }

  /// The `turns` list of a file this version understands, or null when the
  /// file is truncated, not JSON, not valid UTF-8, from another version, or
  /// shaped in a way that leaves no list of turns to read.
  Future<List<Object?>?> _readRows(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['v'] != _version) return null;
      final turns = json['turns'];
      return turns is List ? turns : null;
    } catch (_) {
      return null;
    }
  }

  /// Renames an unreadable chat file to `<id>.json.unreadable-<time>`, beside
  /// where it was, so the next [save] starts a new file instead of replacing
  /// it.
  ///
  /// Renamed rather than deleted: a truncated write still holds most of the
  /// conversation, and a file from a newer build is perfectly good to that
  /// build. Either way it stays where `ls ~/.neurova/chats` shows it. The
  /// suffix keeps it off `*.json`, and a sanitised chat id has no dots, so it
  /// can never be mistaken for a chat file.
  Future<void> _setAside(String chatId, File file) async {
    try {
      final n = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      // No colons: they are not legal in a Windows file name.
      final base = '${file.path}.unreadable-'
          '${n.year}${two(n.month)}${two(n.day)}-'
          '${two(n.hour)}${two(n.minute)}${two(n.second)}';
      // On POSIX a rename replaces whatever is at the target, so two files set
      // aside in the same second must not share a name — that would trade one
      // kept copy for the other.
      var target = base;
      for (var i = 2;
          await FileSystemEntity.type(target, followLinks: false) !=
              FileSystemEntityType.notFound;
          i++) {
        target = '$base-$i';
      }
      await file.rename(target);
    } catch (_) {
      // It could not be moved, so it may still be where the next save would
      // write. [save] skips this chat for as long as it is.
      _blocked.add(chatId);
    }
  }

  Future<void> clear(String chatId) async {
    final file = home.chatFile(chatId);
    if (await file.exists()) await file.delete();
  }
}

/// Mirrors the user's memories into `~/.neurova/memory` as markdown.
///
/// The server stays authoritative — memories are created and deleted there,
/// and this never writes back. What it buys is reach: the agent running ON the
/// phone can `grep ~/.neurova/memory` without a round-trip, and so can the
/// user. A memory the user cannot read is one they cannot correct, and this
/// product's whole claim is that the machine is theirs.
///
/// One file per memory, named by category and id so the directory sorts into
/// something browsable, plus an INDEX.md. The mirror is rewritten whole on
/// each sync: memories are tens of items, and reconciling deletes by hand is
/// how a mirror silently keeps a memory the user thought they had removed.
class MemoryMirror {
  MemoryMirror(this.home);

  final NeurovaHome home;

  /// [entries] is (id, category, importance, content, createdAt).
  Future<void> sync(List<MirroredMemory> entries) async {
    await home.ensure();
    final dir = home.memory;

    // Clear first. A stale file for a deleted memory is worse than no mirror:
    // the agent would read it and act on something the user revoked.
    for (final f in dir.listSync()) {
      if (f is File && f.path.endsWith('.md')) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }

    final index = StringBuffer()
      ..writeln('# Memory')
      ..writeln()
      ..writeln('Mirrored from your CyberNeurova account. Read-only — edits '
          'here are overwritten on the next sync, and deleting a file does '
          'not delete the memory. Manage them in the app under Settings › '
          'Memory.')
      ..writeln();

    for (final e in entries) {
      final file = File('${dir.path}/${e.fileName}');
      await file.writeAsString(e.toMarkdown());
      index.writeln('- `${e.fileName}` — ${e.oneLine}');
    }

    if (entries.isEmpty) index.writeln('_Nothing stored yet._');
    await File('${dir.path}/INDEX.md').writeAsString(index.toString());
  }
}

/// One memory, in the shape the mirror needs.
class MirroredMemory {
  const MirroredMemory({
    required this.id,
    required this.category,
    required this.importance,
    required this.content,
    this.createdAt,
  });

  final String id;
  final String category;
  final int importance;
  final String content;
  final DateTime? createdAt;

  String get fileName {
    final safeCat =
        category.replaceAll(RegExp(r'[^a-z0-9_-]', caseSensitive: false), '');
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${safeCat.isEmpty ? 'context' : safeCat}-$safeId.md';
  }

  /// First line, trimmed to something that fits an index entry.
  String get oneLine {
    final first = content.trim().split('\n').first.trim();
    return first.length > 80 ? '${first.substring(0, 79)}…' : first;
  }

  String toMarkdown() => [
        '---',
        'id: $id',
        'category: $category',
        'importance: $importance',
        if (createdAt != null) 'created: ${createdAt!.toIso8601String()}',
        '---',
        '',
        content.trim(),
        '',
      ].join('\n');
}
