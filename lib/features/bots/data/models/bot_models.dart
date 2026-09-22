import 'package:cyberneurova_mobile/features/bots/data/models/coerce.dart';

/// Agent Contacts (bot-section) data models — the client half of
/// `cyberneurova_core/docs/BOT_SECTION_API.md` §2.
///
/// Hand-written (not freezed) and defensively parsed, matching
/// `core/agent/agent_frame.dart`: `tryParse` returns null for anything it
/// can't make sense of, callers skip rather than throw, and the raw map is
/// kept where a generic renderer might still use unknown fields.

/// An agent contact — the "who" you DM. Only the fields the client renders
/// are lifted out; the engine entity carries more (ownerUserId, boundSection,
/// workdir, projectId, …) that P1 doesn't need.
class BotAgent {
  const BotAgent({
    required this.agentId,
    required this.name,
    this.title,
    this.description,
    this.avatar,
    this.model,
    this.capabilities = const [],
    this.pinned = false,
    this.archivedAt,
  });

  final String agentId;
  final String name;
  final String? title;
  final String? description;
  final String? avatar;
  final String? model;

  /// Tool whitelist the client MUST enforce at its device tool-gate when it
  /// runs this agent on-device (RULE #1). Carried through for P2; unused in P1.
  final List<String> capabilities;
  final bool pinned;
  final String? archivedAt;

  bool get isArchived => archivedAt != null;

  static BotAgent? tryParse(Object? raw) {
    final m = asMap(raw);
    if (m == null) return null;
    final id = asString(m['agentId']) ?? asString(m['id']);
    final name = asString(m['name']);
    if (id == null || name == null) return null;
    return BotAgent(
      agentId: id,
      name: name,
      title: asString(m['title']),
      description: asString(m['description']),
      avatar: asString(m['avatar']),
      model: asString(m['model']),
      capabilities: asStringList(m['capabilities']),
      pinned: asBool(m['pinned']),
      archivedAt: asString(m['archivedAt']),
    );
  }

  /// Parses `{ agents: [...] }` (or a bare list).
  static List<BotAgent> listFrom(Object? raw) {
    final list = asList(asMap(raw)?['agents'] ?? raw);
    return [
      for (final e in list)
        if (tryParse(e) case final a?) a,
    ];
  }
}

/// A conversation. `roomId` is the universal chat/contact id (§2).
class BotRoom {
  const BotRoom({
    required this.roomId,
    required this.type,
    this.title,
    this.folderId,
    this.projectId,
    this.pinned = false,
    this.archivedAt,
    this.updatedAt,
  });

  final String roomId;

  /// `dm` | `group`.
  final String type;
  final String? title;
  final String? folderId;
  final String? projectId;
  final bool pinned;
  final String? archivedAt;

  /// Last-activity time — the server returns rooms newest-first by this.
  final DateTime? updatedAt;

  bool get isDm => type == 'dm';
  bool get isGroup => type == 'group';
  bool get isArchived => archivedAt != null;

  static BotRoom? tryParse(Object? raw) {
    final m = asMap(raw);
    if (m == null) return null;
    final id = asString(m['roomId']) ?? asString(m['id']);
    if (id == null) return null;
    return BotRoom(
      roomId: id,
      type: asStringOr(m['type'], 'dm'),
      title: asString(m['title']),
      folderId: asString(m['folderId']),
      projectId: asString(m['projectId']),
      pinned: asBool(m['pinned']),
      archivedAt: asString(m['archivedAt']),
      updatedAt: DateTime.tryParse(asString(m['updatedAt']) ?? ''),
    );
  }

  /// Parses `{ rooms: [...] }` (or a bare list).
  static List<BotRoom> listFrom(Object? raw) {
    final list = asList(asMap(raw)?['rooms'] ?? raw);
    return [
      for (final e in list)
        if (tryParse(e) case final r?) r,
    ];
  }
}

/// One typed block inside a message. Block `type`s (§2): text, image,
/// file_ref, task_started, task_progress, task_result, approval_request,
/// question, card. P1 renders `text`; every other kind is kept whole in
/// [raw] for P2 (cards / approvals) and forward-compat.
class BotBlock {
  const BotBlock({required this.type, this.text, this.raw = const {}});

  final String type;
  final String? text;
  final Map<String, dynamic> raw;

  static BotBlock? tryParse(Object? raw) {
    final m = asMap(raw);
    if (m == null) return null;
    final type = asString(m['type']);
    if (type == null) return null;
    return BotBlock(type: type, text: asString(m['text']), raw: m);
  }
}

/// One selectable answer for a `question` block. Accepts a bare string or an
/// object under any of the common label/value keys — the emitter shapes aren't
/// frozen (§9 agent↔agent persistence is a TODO), so parse tolerantly.
class BotOption {
  const BotOption({required this.label, required this.value});

  final String label;
  final String value;

  static BotOption? tryParse(Object? raw) {
    if (raw is String) {
      final s = raw.trim();
      return s.isEmpty ? null : BotOption(label: s, value: s);
    }
    final m = asMap(raw);
    if (m == null) return null;
    final label = asString(m['label']) ??
        asString(m['text']) ??
        asString(m['title']) ??
        asString(m['value']) ??
        asString(m['id']);
    if (label == null) return null;
    final value = asString(m['value']) ?? asString(m['id']) ?? label;
    return BotOption(label: label, value: value);
  }
}

/// Typed views over a block's [BotBlock.raw], each with fallbacks across the
/// field names an emitter might use. Rendering reads these instead of poking
/// the raw map, keeping the tolerance in one place.
extension BotBlockView on BotBlock {
  /// The block's human-readable line, whatever key it landed under.
  String? get displayText =>
      (text != null && text!.trim().isNotEmpty ? text : null) ??
      asString(raw['prompt']) ??
      asString(raw['question']) ??
      asString(raw['summary']) ??
      asString(raw['title']) ??
      asString(raw['body']) ??
      asString(raw['message']);

  /// Bound run — answers/approvals must carry it (§5b). Falls back to the
  /// message's `runId` via [runIdOr].
  String? get runId => asString(raw['runId']) ?? asString(raw['run_id']);

  String runIdOr(String? messageRunId) => runId ?? messageRunId ?? '';

  /// Block-scoped id (question / approval) if the emitter set one.
  String? get refId =>
      asString(raw['id']) ??
      asString(raw['questionId']) ??
      asString(raw['approvalId']) ??
      asString(raw['callId']);

  List<BotOption> get options => [
        for (final o in asList(raw['options'] ?? raw['choices']))
          if (BotOption.tryParse(o) case final x?) x,
      ];

  /// A run/approval risk hint, if present ('low' | 'high' | …).
  String? get risk => asString(raw['risk']);

  /// What a `task_*` block reports.
  String? get status => asString(raw['status']);

  // ---- file_ref ----
  String? get fileName =>
      asString(raw['name']) ?? asString(raw['filename']) ?? asString(raw['fileName']);
  String? get fileId => asString(raw['fileId']) ?? asString(raw['id']);
  String? get fileUrl => asString(raw['url']);
  String? get mime => asString(raw['mime']) ?? asString(raw['contentType']);
  int? get sizeBytes => asInt(raw['sizeBytes']) ?? asInt(raw['size']);
}

/// A message. `(roomId, seq)` is monotonic — the ordering + catch-up backbone
/// (§2, §4). The client tracks the highest [seq] it has per room and asks the
/// server to replay from there on reconnect.
class BotMessage {
  const BotMessage({
    required this.messageId,
    required this.roomId,
    required this.seq,
    required this.senderId,
    required this.senderType,
    this.blocks = const [],
    this.runId,
    this.clientNonce,
  });

  final String messageId;
  final String roomId;
  final int seq;
  final String senderId;

  /// `human` | `agent`.
  final String senderType;
  final List<BotBlock> blocks;
  final String? runId;
  final String? clientNonce;

  bool get isFromAgent => senderType == 'agent';

  /// Joined text of all `text` blocks — what a plain chat bubble shows.
  String get text => blocks
      .where((b) => b.type == 'text')
      .map((b) => b.text ?? '')
      .join('\n')
      .trim();

  static BotMessage? tryParse(Object? raw) {
    final m = asMap(raw);
    if (m == null) return null;
    final id = asString(m['messageId']) ?? asString(m['id']);
    final roomId = asString(m['roomId']);
    final seq = asInt(m['seq']);
    if (id == null || roomId == null || seq == null) return null;
    return BotMessage(
      messageId: id,
      roomId: roomId,
      seq: seq,
      senderId: asStringOr(m['senderId'], ''),
      senderType: asStringOr(m['senderType'], 'agent'),
      blocks: [
        for (final b in asList(m['blocks']))
          if (BotBlock.tryParse(b) case final bb?) bb,
      ],
      runId: asString(m['runId']),
      clientNonce: asString(m['clientNonce']),
    );
  }

  /// Parses `{ messages: [...] }` (or a bare list), ascending by seq.
  static List<BotMessage> listFrom(Object? raw) {
    final list = asList(asMap(raw)?['messages'] ?? raw);
    return [
      for (final e in list)
        if (tryParse(e) case final msg?) msg,
    ];
  }
}

/// A device heartbeat row (§2). Drives "offline desktop = read-only remote":
/// before offering "run", the client checks a desktop is [online].
class BotPresence {
  const BotPresence({
    required this.deviceId,
    required this.role,
    required this.status,
    this.online = false,
    this.lastSeenAt,
  });

  final String deviceId;

  /// `desktop` | `mobile` | `web`.
  final String role;

  /// `online` | `offline`.
  final String status;

  /// Seen within the liveness window (server-computed).
  final bool online;
  final String? lastSeenAt;

  static BotPresence? tryParse(Object? raw) {
    final m = asMap(raw);
    if (m == null) return null;
    final device = asString(m['deviceId']);
    if (device == null) return null;
    return BotPresence(
      deviceId: device,
      role: asStringOr(m['role'], 'unknown'),
      status: asStringOr(m['status'], 'offline'),
      online: asBool(m['online']),
      lastSeenAt: asString(m['lastSeenAt']),
    );
  }

  /// Parses `{ presence: [...] }` (or a bare list).
  static List<BotPresence> listFrom(Object? raw) {
    final list = asList(asMap(raw)?['presence'] ?? raw);
    return [
      for (final e in list)
        if (tryParse(e) case final p?) p,
    ];
  }
}

extension BotPresenceList on List<BotPresence> {
  /// True if any DESKTOP device is online — the gate for offering "run".
  bool get hasOnlineDesktop => any((p) => p.role == 'desktop' && p.online);
}
