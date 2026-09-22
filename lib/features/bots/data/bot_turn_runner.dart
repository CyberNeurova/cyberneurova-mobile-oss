import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/agent_session_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/data/repositories/bot_repository.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

final botTurnRunnerProvider =
    Provider<BotTurnRunner>((ref) => BotTurnRunner(ref));

/// PHASE-B B1 — runs ONE agent turn on-device for a DM, sourcing the prompt
/// from the bot-section room and posting `task_started` → `task_result` blocks.
/// **B1-proper: uses `/agent/run` with the real device tool schemas**, driving
/// the frames through the existing [AgentSession] so `executor: "device"` tool
/// calls run on the phone and their results POST back — the agent can actually
/// *do* things, not just chat.
///
/// SPIKE SHORTCUTS still in place (see `docs/BOT_EXECUTOR_PHASE_B_SCOPE.md`):
///  - The transport is chat-scoped, so we fold room history into one turn
///    against a reusable **scratch chat** (that chat's id also keys the reused
///    session + device executor). Production wants a room-scoped run mode.
///  - No presence gate (B0), no run-record lifecycle, no director (B3).
///  - Approvals are B2: if the model requests one, no UI answers it yet, so the
///    run relies on the 5-min timeout. Keep B1 prompts read-only for now.
class BotTurnRunner {
  BotTurnRunner(this._ref);

  final Ref _ref;

  /// One scratch chat reused for all executor turns — its id also keys the
  /// reused [agentSessionProvider] + [deviceExecutorProvider]. SPIKE ONLY.
  String? _scratchChatId;

  BotRepository get _bots => _ref.read(botRepositoryProvider);
  ChatRepository get _chat => _ref.read(chatRepositoryProvider);

  Future<String> _scratchChat() async {
    final cached = _scratchChatId;
    if (cached != null) return cached;
    // Create through the LIST notifier with an agent-surface section: device
    // tools are gated on the chat's `section` (via isAgentSessionProvider,
    // read from chatListProvider), and a plain 'chat' section yields a NULL
    // device executor → every device tool refused. 'code' opts the scratch
    // context into on-device tools. (The backend drops section; the local list
    // keeps it, which is exactly what the gate reads.)
    final chat = await _ref.read(chatListProvider.notifier).createChat(
          title: 'Bot executor (scratch)',
          section: AppConstants.sectionCode,
        );
    _scratchChatId = chat.id;
    return chat.id;
  }

  Future<void> runTurn({
    required String roomId,
    required String agentId,
    required String userText,
    required List<BotMessage> history,
  }) async {
    final agent = await _bots.getAgent(agentId);
    if (agent == null) return;
    if (!await _mobileIsExecutor()) return _deferToDesktop(roomId);
    await _executeTurn(
      roomId: roomId, agent: agent, userText: userText, history: history);
  }

  /// Runs one resolved agent's turn on-device: task_started → `/agent/run`
  /// (with device tools) → task_result. Callers gate + resolve the agent.
  Future<void> _executeTurn({
    required String roomId,
    required BotAgent agent,
    required String userText,
    required List<BotMessage> history,
  }) async {
    await _post(roomId, agent, type: 'task_started', text: 'On it — thinking…');

    try {
      final chatId = await _scratchChat();
      // The reused session executes `executor: "device"` tool calls on-device
      // and posts their results over its control channel — this is the whole
      // point of B1-proper.
      final session = _ref.read(agentSessionProvider(chatId).notifier);
      final caps = _ref.read(deviceCapabilitiesProvider);

      String? finalText;
      var streamed = '';
      var lastSeq = -1;

      final stream = _chat.streamAgentRun(
        chatId: chatId,
        message: composeBotTurnPrompt(agent, history, userText),
        modelId: agent.model ?? 'cyberneurova-qwen3.8',
        // Present device tools. (Mapping the agent's higher-level
        // `capabilities` → the device-tool whitelist is a follow-up — the
        // vocabularies differ; noted in the scope doc.)
        capabilities: [for (final c in caps.present) c.name],
      );

      await for (final json in stream.timeout(const Duration(minutes: 5))) {
        final seq = json['seq'];
        if (seq is int) {
          if (seq <= lastSeq) continue;
          lastSeq = seq;
        }

        // Device-tool execution happens here: the session runs any
        // `executor:"device"` call and posts the result back.
        final frame = AgentFrame.tryParse(json);
        if (frame != null) {
          session.apply(frame, runId: json['run_id'] as String?);
        }

        final t = _textFromFrame(json);
        if (t != null && t.isNotEmpty) {
          if (json['partial'] == true) {
            streamed += t;
          } else {
            finalText = t; // a complete assistant / result frame replaces
          }
        }

        if (json['type'] == 'error') {
          throw Exception(json['message'] ?? 'run error');
        }
        if (json['type'] == 'result' ||
            json['type'] == 'done' ||
            json['type'] == 'run_finished') {
          break;
        }
      }

      final reply = (finalText ?? streamed).trim();
      await _post(roomId, agent,
          type: 'task_result',
          text: reply.isEmpty ? '(the agent finished with nothing to say)' : reply);
    } catch (e) {
      debugPrint('[bot-executor] turn failed: $e');
      await _post(roomId, agent,
          type: 'task_result',
          status: 'failed',
          text: "The agent couldn't finish this turn.");
    }
  }

  /// The final assistant text out of a run-protocol frame (mirrors the chat
  /// provider's `_textFromFrame`): `result` → its text; a `message` frame → its
  /// text blocks; else the flat `text`/`delta`.
  String? _textFromFrame(Map<String, dynamic> json) {
    if (json['type'] == 'result') return json['result'] as String?;
    final message = json['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String) return content;
      if (content is List) {
        final buf = StringBuffer();
        for (final b in content) {
          if (b is Map && b['type'] == 'text' && b['text'] is String) {
            buf.write(b['text']);
          }
        }
        if (buf.isNotEmpty) return buf.toString();
      }
    }
    final flat = json['text'] ?? json['delta'];
    return flat is String ? flat : null;
  }

  Future<void> _post(
    String roomId,
    BotAgent agent, {
    required String type,
    required String text,
    String? status,
  }) async {
    await _bots.sendMessage(
      roomId,
      blocks: [
        {
          'type': type,
          'text': text,
          if (status != null) 'status': status,
          // Attribute the block to the agent (POST /messages is authored by the
          // human device; the agent identity rides in the block — §2).
          'authorAgentId': agent.agentId,
          'authorName': agent.name,
        },
      ],
      clientNonce: '$type-${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  /// PHASE-B B3 — group turn-taking. Runs the director (`/next-speaker`) and
  /// lets up to [maxResponders] agents reply on-device, sequentially, each
  /// seeing the prior replies. `/next-speaker` resolves `@mention` + the
  /// anti-loop human-gate; the ambiguous case returns `none` (the server
  /// model-pick is a TODO and mobile can't pick without the roster endpoint —
  /// §7), so a group responds to `@mentions` today. The human-gate stops the
  /// loop naturally once agents have spoken.
  Future<void> runGroupTurn({
    required String roomId,
    required String userText,
    int maxResponders = 2,
  }) async {
    if (!await _mobileIsExecutor()) return _deferToDesktop(roomId);
    // Let the human's just-sent message persist so /next-speaker sees the
    // mention. (B3 shortcut; a cleaner path awaits the send's completion.)
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final responded = <String>{};
    for (var i = 0; i < maxResponders; i++) {
      final pick = await _bots.nextSpeaker(roomId);
      final speaker = pick.speaker;
      if (speaker == null || responded.contains(speaker)) break;
      responded.add(speaker);
      final agent = await _bots.getAgent(speaker);
      if (agent == null) continue;
      final history = await _bots.getMessages(roomId);
      await _executeTurn(
        roomId: roomId, agent: agent, userText: userText, history: history);
    }
  }

  // ── B0: executor-role gate ────────────────────────────────────────────────
  /// Mobile is the executor only when no DESKTOP is online (desktop 002/006:
  /// mobile executes as the sole online device; otherwise it's the controller).
  /// Fail-open to true so a presence hiccup never blocks the only device that
  /// can run.
  Future<bool> _mobileIsExecutor() async {
    try {
      return !(await _bots.getPresence()).hasOnlineDesktop;
    } catch (_) {
      return true;
    }
  }

  /// A desktop is online → it is the authority. Post a short note rather than
  /// double-executing. (Mobile → remote-executor hand-off is B4.)
  Future<void> _deferToDesktop(String roomId) => _postSystemCard(
        roomId,
        'A desktop is online — it runs agent turns. Mobile hand-off to a '
        'remote executor lands in B4.',
      );

  Future<void> _postSystemCard(String roomId, String text) async {
    await _bots.sendMessage(
      roomId,
      blocks: [
        {'type': 'card', 'text': text},
      ],
      clientNonce: 'card-${DateTime.now().microsecondsSinceEpoch}',
    );
  }
}

/// Builds the model prompt for one agent turn: the agent's persona, the room
/// transcript (via [botTurnLine], last 30 lines), the latest user text, and a
/// reply instruction. Pure — the unit under test.
String composeBotTurnPrompt(
    BotAgent agent, List<BotMessage> history, String userText) {
  final b = StringBuffer();
  b.writeln('You are ${agent.name}, an AI agent in a chat. You may use your '
      'device tools when the task calls for it.');
  final about = agent.description ?? agent.title;
  if (about != null && about.trim().isNotEmpty) b.writeln(about.trim());
  final lines = [
    for (final m in history)
      if (botTurnLine(m) case final l?) l,
  ];
  if (lines.isNotEmpty) {
    b.writeln('\nConversation so far:');
    for (final l
        in lines.length > 30 ? lines.sublist(lines.length - 30) : lines) {
      b.writeln(l);
    }
  }
  b.writeln('\nUser: $userText');
  b.writeln('\nReply as ${agent.name}. Be concise.');
  return b.toString();
}

/// A "<Author>: <text>" transcript line for a message, or null if it has no
/// conversational text. An agent's reply is a `task_result` block attributed
/// via `authorName` (the message itself is authored by the human device — §2),
/// so the author comes from the blocks, not `senderType`. This is what lets
/// group members see each other's replies.
String? botTurnLine(BotMessage m) {
  String? author;
  final buf = StringBuffer();
  for (final block in m.blocks) {
    final an = block.raw['authorName'];
    if (author == null && an is String && an.isNotEmpty) author = an;
    if (block.type == 'text' || block.type == 'task_result') {
      final t = block.displayText;
      if (t != null && t.trim().isNotEmpty) buf.writeln(t.trim());
    }
  }
  final text = buf.toString().trim();
  if (text.isEmpty) return null;
  return '${author ?? 'User'}: $text';
}
