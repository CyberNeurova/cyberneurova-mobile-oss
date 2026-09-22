import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_stream_frame.dart';

final botRepositoryProvider = Provider<BotRepository>((ref) {
  return BotRepository(ref.watch(apiClientProvider));
});

/// Client for Agent Contacts (bot-section), via the mobile proxy
/// (`/api/mobile/v1/bot/*` → isolated `cn_botsection` instance; inbox/043).
///
/// Every call goes through [ApiClient], whose interceptor attaches the Bearer
/// token and refreshes on 401 — we never touch the token here. Non-member /
/// non-owner reads come back `404` by contract (§7), surfaced as an
/// [AppException] by the error interceptor.
class BotRepository {
  BotRepository(this._client);

  final ApiClient _client;

  // ── Agents (contacts) ──────────────────────────────────────────────────
  Future<List<BotAgent>> listAgents({bool includeArchived = false}) async {
    final res = await _client.get(
      ApiConstants.BOT_AGENTS,
      queryParameters: includeArchived ? {'includeArchived': 'true'} : null,
    );
    return BotAgent.listFrom(res.data);
  }

  Future<BotAgent?> createAgent({
    required String name,
    String? title,
    String? description,
    String? model,
    String? instructions,
    List<String>? capabilities,
    String? agentId,
  }) async {
    final res = await _client.post(ApiConstants.BOT_AGENTS, data: {
      'name': name,
      if (agentId != null) 'agentId': agentId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (model != null) 'model': model,
      if (instructions != null) 'instructions': instructions,
      if (capabilities != null) 'capabilities': capabilities,
    });
    return BotAgent.tryParse(_unwrap(res.data, 'agent'));
  }

  /// One agent by id (for the profile view). `404` if not the caller's (§3).
  Future<BotAgent?> getAgent(String agentId) async {
    final res = await _client.get(ApiConstants.botAgentById(agentId));
    return BotAgent.tryParse(_unwrap(res.data, 'agent'));
  }

  // ── Rooms ──────────────────────────────────────────────────────────────
  Future<List<BotRoom>> listRooms() async {
    final res = await _client.get(ApiConstants.BOT_ROOMS);
    return BotRoom.listFrom(res.data);
  }

  /// Opens a DM room with one of the caller's own agents. `agentId` is
  /// required for a DM and must be the caller's (§3).
  Future<BotRoom?> createDmRoom(
    String agentId, {
    String? roomId,
    String? title,
  }) async {
    final res = await _client.post(ApiConstants.BOT_ROOMS, data: {
      'type': 'dm',
      'agentId': agentId,
      if (roomId != null) 'roomId': roomId,
      if (title != null) 'title': title,
    });
    return BotRoom.tryParse(_unwrap(res.data, 'room'));
  }

  /// Creates a group room in the Bot Chat section. Group rooms are pro/pro_max —
  /// a free/starter caller gets `403 feature_requires_upgrade` on create (§8),
  /// which the UI gates on. (A group is just a group that lives in Bot Chat —
  /// no Project link; desktop `mobile/desktop/006`.)
  Future<BotRoom?> createGroupRoom({
    String? title,
    String? roomId,
  }) async {
    final res = await _client.post(ApiConstants.BOT_ROOMS, data: {
      'type': 'group',
      if (title != null) 'title': title,
      if (roomId != null) 'roomId': roomId,
    });
    return BotRoom.tryParse(_unwrap(res.data, 'room'));
  }

  /// The caller's group rooms (non-archived), most-relevant first — the Groups
  /// section of the Bot Chat list.
  Future<List<BotRoom>> listGroups() async {
    final rooms = await listRooms();
    return [for (final r in rooms) if (r.isGroup && !r.isArchived) r];
  }

  /// Renames a room (owner-scoped `POST /rooms/:id {title}`).
  Future<BotRoom?> renameRoom(String roomId, String title) async {
    final res = await _client.post(
      ApiConstants.botRoomById(roomId),
      data: {'title': title},
    );
    return BotRoom.tryParse(_unwrap(res.data, 'room'));
  }

  /// Hard-deletes a room + its messages/runs/commands/files (owner-scoped).
  Future<void> deleteRoom(String roomId) async {
    await _client.delete(ApiConstants.botRoomById(roomId));
  }

  /// Adds one of the caller's agents to a room as a participant (§3).
  Future<void> addAgent(String roomId, String agentId) async {
    await _client.post(
      ApiConstants.botRoomParticipants(roomId),
      data: {'memberId': agentId, 'memberType': 'agent'},
    );
  }

  // ── Messages ────────────────────────────────────────────────────────────
  /// Catch-up read (ascending seq). Pass [afterSeq] with the highest seq you
  /// already hold so the server returns only the gap.
  Future<List<BotMessage>> getMessages(
    String roomId, {
    int? afterSeq,
    int? limit,
  }) async {
    final res = await _client.get(
      ApiConstants.botRoomMessages(roomId),
      queryParameters: {
        if (afterSeq != null) 'after_seq': afterSeq,
        if (limit != null) 'limit': limit,
      },
    );
    return BotMessage.listFrom(res.data);
  }

  /// Sends a text message (persisted AND relayed live). [clientNonce] makes a
  /// network retry idempotent — mint a fresh one per user send so a resend can
  /// never double-post.
  Future<BotMessage?> sendMessage(
    String roomId, {
    String? text,
    List<Map<String, dynamic>>? blocks,
    String? messageId,
    String? clientNonce,
  }) async {
    final res = await _client.post(
      ApiConstants.botRoomMessages(roomId),
      data: {
        if (blocks != null) 'blocks': blocks,
        if (blocks == null && text != null) 'text': text,
        if (messageId != null) 'messageId': messageId,
        if (clientNonce != null) 'clientNonce': clientNonce,
      },
    );
    return BotMessage.tryParse(_unwrap(res.data, 'message'));
  }

  // ── Director (group turn-taking) ────────────────────────────────────────
  /// Who speaks next in a group room (§3). The engine resolves `@mention` +
  /// the anti-loop human-gate and returns that agent; the ambiguous case is
  /// `none` (the model-backed pick is a server TODO). `reason` ∈
  /// `mention | director | human_gate | none`.
  Future<({String? speaker, String reason})> nextSpeaker(String roomId) async {
    final res = await _client.get(ApiConstants.botRoomNextSpeaker(roomId));
    final data = res.data;
    final map = data is Map ? data : const {};
    final speaker = map['speaker'];
    final reason = map['reason'];
    return (
      speaker: speaker is String && speaker.isNotEmpty ? speaker : null,
      reason: reason is String ? reason : 'none',
    );
  }

  // ── Commands (up-lane) ──────────────────────────────────────────────────
  /// Enqueues an up-lane command (§5b). Answering a `question` or an
  /// `approval_request` from the room is exactly this: a nonce'd command bound
  /// to the block's `runId`, durably queued so the executor resumes the
  /// suspended run for real — even if it's momentarily offline. `answer` /
  /// `approve` / `reject` / `steer` / `cancel` all require [runId].
  ///
  /// [clientNonce] must be STABLE across retries of the same logical action so
  /// a resend can never enqueue a second command — mint it once per prompt.
  Future<bool> postCommand(
    String roomId, {
    required String kind,
    String? runId,
    Map<String, dynamic>? payload,
    String? clientNonce,
  }) async {
    final res = await _client.post(
      ApiConstants.botRoomCommands(roomId),
      data: {
        'kind': kind,
        if (runId != null && runId.isNotEmpty) 'runId': runId,
        if (payload != null) 'payload': payload,
        if (clientNonce != null) 'clientNonce': clientNonce,
      },
    );
    final cmd = _unwrap(res.data, 'command');
    return cmd is Map; // 201 { command } on success
  }

  // ── Presence ────────────────────────────────────────────────────────────
  Future<List<BotPresence>> getPresence() async {
    final res = await _client.get(ApiConstants.BOT_PRESENCE);
    return BotPresence.listFrom(res.data);
  }

  /// Advertises this device as an online executor candidate (role `mobile`).
  /// The server fans a `presence` event to the user's other devices (§3).
  Future<void> heartbeat({String status = 'online'}) async {
    await _client.post(
      ApiConstants.BOT_PRESENCE,
      data: {'role': 'mobile', 'status': status},
    );
  }

  // ── Live stream (multiplexed SSE, ALL rooms) ────────────────────────────
  /// One SSE stream for every room the user is in (§4 — never one-per-room).
  /// Unrecognised frames are dropped by [BotStreamEvent.tryParse]. The caller
  /// de-dups by seq and, on reconnect, re-subscribes and catches up via
  /// [getMessages] from its last seq per room.
  Stream<BotStreamEvent> streamEvents() async* {
    await for (final sse in _client.streamSse(ApiConstants.BOT_STREAM)) {
      final decoded = _tryDecodeObject(sse.data);
      if (decoded == null) continue;
      final event = BotStreamEvent.tryParse(decoded, eventName: sse.event);
      if (event != null) yield event;
    }
  }

  // POST responses may return the entity bare or wrapped ({agent:…}); accept
  // either without guessing.
  Object? _unwrap(Object? data, String key) {
    if (data is Map && data[key] != null) return data[key];
    return data;
  }

  Map<String, dynamic>? _tryDecodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
