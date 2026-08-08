import 'dart:convert';
import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';

/// What a run leaves behind when the app closes.
///
/// ## The gap this fills
///
/// Nothing about a run was persisted. Close the app mid-run — or simply leave
/// the chat and come back — and the transcript was empty: no record that the
/// agent had scanned anything, written anything or failed at anything. The
/// conversation survived, because the server stores messages; everything the
/// agent DID did not, because only this client ever knew about it.
///
/// On a phone that is not an edge case. The app is backgrounded constantly,
/// and Android will kill it for memory while a long run is going.
///
/// ## Why the tool cards and not the prose
///
/// Assistant and user text already round-trips through `/chat/:id/messages`,
/// so persisting it here would give two sources for the same thing and a
/// reconciliation problem the first time they disagreed. Tool activity has no
/// other home, so it is the part worth writing down — along with the `run_id`,
/// without which a resume cannot even be addressed.
///
/// Deliberately not a database: one small JSON file per chat, rewritten whole.
/// A run's card list is tens of entries, and the cost of that is far below the
/// cost of a schema to migrate later.
class RunStore {
  RunStore(this.directory);

  /// Where the files live. Injected so tests do not need a plugin.
  final Directory directory;

  static const _version = 1;

  File _fileFor(String chatId) {
    // The chat id is a server-generated UUID, but sanitise anyway: this is a
    // path, and one day something else will be passed in.
    final safe = chatId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return File('${directory.path}/run_$safe.json');
  }

  /// Writes the run's tool activity. Removes the file when there is none, so
  /// an empty chat does not leave a husk behind.
  Future<void> save(String chatId, {String? runId, required AgentTranscript transcript}) async {
    final cards = [
      for (final item in transcript.items)
        if (item is ToolCardItem) _encodeCard(item),
    ];

    final file = _fileFor(chatId);
    if (cards.isEmpty && runId == null) {
      if (await file.exists()) await file.delete();
      return;
    }

    if (!await directory.exists()) await directory.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'v': _version,
      'run_id': runId,
      'saved_at': DateTime.now().toIso8601String(),
      'cards': cards,
    }));
  }

  /// Reads back what [save] wrote, or null when there is nothing.
  ///
  /// Any failure returns null rather than throwing: a corrupt or
  /// future-versioned file must degrade to "no history", never to a chat that
  /// will not open.
  Future<RestoredRun?> load(String chatId) async {
    try {
      final file = _fileFor(chatId);
      if (!await file.exists()) return null;

      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      if (json['v'] != _version) return null;

      final cards = <ToolCardItem>[];
      for (final raw in (json['cards'] as List? ?? const [])) {
        final card = _decodeCard(raw);
        if (card != null) cards.add(card);
      }
      return RestoredRun(runId: json['run_id'] as String?, cards: cards);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String chatId) async {
    final file = _fileFor(chatId);
    if (await file.exists()) await file.delete();
  }

  static Map<String, dynamic> _encodeCard(ToolCardItem c) => {
        'call_id': c.callId,
        'tool': c.tool,
        if (c.title != null) 'title': c.title,
        'input': c.input,
        // A card that was RUNNING when the app died did not survive the
        // process. Recording it as running would show a spinner that can never
        // stop, so it is written down as what it actually is: interrupted.
        'state': (c.state == ToolCardState.running ||
                c.state == ToolCardState.pending)
            ? ToolCardState.failed.name
            : c.state.name,
        if (c.state == ToolCardState.running || c.state == ToolCardState.pending)
          'error': 'Interrupted — the app closed while this was running.'
        else if (c.error != null)
          'error': c.error,
        if (c.summary != null) 'summary': c.summary,
        if (c.output != null) 'output': c.output,
        if (c.startedAt != null) 'started_at': c.startedAt!.toIso8601String(),
        if (c.endedAt != null) 'ended_at': c.endedAt!.toIso8601String(),
        'artifacts': [
          for (final a in c.artifacts)
            {
              'name': a.name,
              if (a.url != null) 'url': a.url,
              if (a.mimeType != null) 'mime_type': a.mimeType,
              if (a.sizeBytes != null) 'size_bytes': a.sizeBytes,
            },
        ],
      };

  static ToolCardItem? _decodeCard(Object? raw) {
    if (raw is! Map) return null;
    final callId = raw['call_id'];
    final tool = raw['tool'];
    if (callId is! String || tool is! String) return null;

    final card = ToolCardItem(
      callId: callId,
      tool: tool,
      title: raw['title'] as String?,
      input: Map<String, dynamic>.from(raw['input'] as Map? ?? const {}),
      state: ToolCardState.values.firstWhere(
        (s) => s.name == raw['state'],
        orElse: () => ToolCardState.failed,
      ),
    )
      ..summary = raw['summary'] as String?
      ..output = raw['output'] as String?
      ..error = raw['error'] as String?
      ..startedAt = DateTime.tryParse(raw['started_at'] as String? ?? '')
      ..endedAt = DateTime.tryParse(raw['ended_at'] as String? ?? '');

    card.artifacts = [
      for (final a in (raw['artifacts'] as List? ?? const []))
        if (AgentArtifact.tryParse(a) case final parsed?) parsed,
    ];
    return card;
  }
}

/// What came back off disk.
class RestoredRun {
  const RestoredRun({required this.runId, required this.cards});

  /// Needed to address a resume. Null means the run can be shown but not
  /// continued.
  final String? runId;

  final List<ToolCardItem> cards;

  bool get isEmpty => cards.isEmpty && runId == null;
}
