import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/constants/dev_flags.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/dev_mock_chat_repository.dart';

/// Whether a run frame represents the run getting anywhere.
///
/// `/agent/run` emits a `heartbeat` every 15 seconds for as long as the
/// connection is open. It says the socket is alive; it says nothing about the
/// run. The only stall guard on the client is `Stream.timeout`, which measures
/// the gap between *events* — so a heartbeat resets it, and a run that dies
/// server-side spins "Thinking…" forever with no failure, no Retry and no way
/// for the user to tell it is never coming back.
///
/// Observed on device 2026-08-05: a Console run produced `run_started`,
/// `system`, `render_hint`, `system`, and then 15-second heartbeats
/// indefinitely — the model was never invoked. The 5-minute idle timeout never
/// fired because the heartbeats kept it alive. Dropping them here makes that
/// timeout mean what it was written to mean.
///
/// Nothing downstream reads a heartbeat: `AgentFrame.tryParse` does not know
/// the type and the text extractor ignores it.
bool isProgressFrame(Map<String, dynamic> frame) => frame['type'] != 'heartbeat';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  // Dev sandbox: with DEV_AUTH_BYPASS the whole chat feature runs against an
  // in-memory mock so UI work needs no account/network (docs/SETUP.md).
  if (devAuthBypass) {
    return DevMockChatRepository(ref.watch(apiClientProvider));
  }
  return ChatRepository(ref.watch(apiClientProvider));
});

class ChatRepository {
  ChatRepository(this._client);
  final ApiClient _client;

  /// Lists chats, optionally restricted to one section.
  ///
  /// [section] is one of `chat`, `code`, `research`, `shell`; the server
  /// paginates WITHIN the filter and treats rows written before the field
  /// existed as `chat`. Omit it for the legacy all-sections list.
  ///
  /// This is the fix for the owner's "the app only shows 2 chats". The page
  /// limit used to be spent on all sections at once, so a day of Console
  /// testing — 14 shell sessions and 4 research ones in the newest 20 rows —
  /// pushed his actual conversations out of the only window the phone could
  /// see. Filtering client-side could not help: the rows never arrived.
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.CHAT,
      queryParameters: {
        'limit': AppConstants.defaultPageLimit,
        // `endingBefore`, NOT `startingAfter`. The list is newest-first, so
        // the next page is OLDER than the cursor; `startingAfter` asks for
        // newer rows, which overlap the page you already have. That was the
        // other half of "can't page past 20" — the request
        // succeeded and returned rows we had already shown.
        if (cursor != null) 'endingBefore': cursor,
        if (section != null) 'section': section,
      },
    );
    return ChatListResponse.fromJson(res.data!);
  }

  Future<ChatModel> createChat({String? title, String section = 'chat'}) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.CHAT,
      data: {
        if (title != null) 'title': title,
        'section': section,
      },
    );
    // Tolerate the response being wrapped as {chat: {...}} or {data: {...}}
    // OR bare. Same pattern we apply elsewhere — the backend API isn't
    // consistent across routes about wrapping.
    final body = res.data!;
    // Sahachiel: guard each unwrap with `is Map` - a present-but-wrong-typed
    // `chat`/`data` field used to throw a CastError instead of falling through.
    final inner = (body['chat'] is Map<String, dynamic>
            ? body['chat'] as Map<String, dynamic>
            : null) ??
        (body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : null) ??
        body;
    final chat = ChatModel.fromJson(inner);
    if (chat.id.isEmpty) {
      // Couldn't parse an id from the response shape. Surface this as a
      // real error rather than letting the caller navigate to /chats/
      // (empty path), which falls back to bootstrap and looks like the
      // app is stuck in a loop.
      throw Exception(
        "Server didn't return a chat id. Response shape: ${body.keys.toList()}",
      );
    }
    return chat;
  }

  Future<({ChatModel chat, List<MessageModel> messages})> getChatWithMessages(
    String id,
  ) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.chatById(id),
    );
    final data = res.data!;
    // Defensive shape handling — the backend response on empty chats has
    // historically returned `messages: null` or omitted the field entirely.
    // Also handle the case where the chat object is at the top level instead
    // of nested under `chat:`.
    // Sahachiel: every read here is defensive - the chat object may be nested or
    // top-level, `messages` may be null/omitted or wrong-typed, and a list entry
    // may not be a map. `as` casts on any of these crashed the chat screen on a
    // drifted payload; now they degrade (skip the bad entry) instead.
    final chatJson = data['chat'] is Map<String, dynamic>
        ? data['chat'] as Map<String, dynamic>
        : data;
    final messagesRaw = data['messages'] is List ? data['messages'] as List : const [];
    return (
      chat: ChatModel.fromJson(chatJson),
      messages: messagesRaw
          .whereType<Map<String, dynamic>>()
          .map(MessageModel.fromJson)
          .toList(),
    );
  }

  Future<MessagesResponse> getMessages(
    String chatId, {
    String? cursor,
    int limit = AppConstants.messagesPageLimit,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.chatMessages(chatId),
      queryParameters: {
        'limit': limit,
        // Messages paginate on `before` (older) / `after` (newer), NOT
        // `endingBefore` (that's the /chat LIST cursor). Wrong name = the
        // server ignores it and re-serves page one. Three cursor spellings
        // across two endpoints, so check the route before copying one.
        if (cursor != null) 'before': cursor,
      },
    );
    return MessagesResponse.fromJson(res.data!);
  }

  Future<ChatModel> updateChat(
    String id, {
    String? title,
    String? visibility,
  }) async {
    final res = await _client.patch<Map<String, dynamic>>(
      ApiConstants.chatById(id),
      data: {
        if (title != null) 'title': title,
        if (visibility != null) 'visibility': visibility,
      },
    );
    // Response is `{chat:{…}}` — unwrap like createChat/getChatWithMessages.
    final inner = res.data!['chat'] is Map<String, dynamic>
        ? res.data!['chat'] as Map<String, dynamic>
        : res.data!;
    return ChatModel.fromJson(inner);
  }

  Future<void> deleteChat(String id) => _client.delete(ApiConstants.chatById(id));

  /// Sharing — update visibility (private | shared | public).
  Future<void> updateVisibility(String chatId, String visibility) async {
    await _client.patch(
      ApiConstants.chatById(chatId),
      data: {'visibility': visibility},
    );
  }

  /// Add a user (by email) to a shared chat.
  Future<void> shareWithEmail(String chatId, String email) async {
    await _client.post(
      ApiConstants.chatShare(chatId),
      // Real contract: {emails: string[1-10], permission?}. Singular `email`
      // 400s.
      data: {'emails': [email]},
    );
  }

  /// Remove a user's access to a shared chat.
  Future<void> unshareWithEmail(String chatId, String email) async {
    await _client.delete(
      ApiConstants.chatShare(chatId),
      data: {'email': email},
    );
  }

  /// Returns the current share state (visibility + shared users).
  Future<Map<String, dynamic>> getShareInfo(String chatId) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.chatShare(chatId),
    );
    return res.data!;
  }

  /// Streams an AI response for the given [chatId].
  /// Yields [StreamEvent]s as they arrive via NDJSON.
  ///
  /// **API quirk (2026-06):** the server's zod schema requires `modelId`
  /// (not `model`) and it's mandatory. The doc says `model` and optional —
  /// the route handler disagrees. We send `modelId`. Default to the free-tier
  /// model `tiny-neurova` if caller doesn't specify.
  Stream<StreamEvent> streamCompletion({
    required String chatId,
    required String message,
    String modelId = 'tiny-neurova',
    List<Map<String, dynamic>>? attachments,
    bool forceWebSearch = false,
    String? deviceContext,
  }) {
    return _client
        .stream(
          ApiConstants.chatComplete(chatId),
          data: {
            'message': message,
            'modelId': modelId,
            if (attachments != null) 'attachments': attachments,
            // the backend API: when true, the server bypasses its
            // detectAutoSearch heuristic and runs webSearch on the
            // verbatim message. Replaces the build-12 "search the web
            // for ..." prefix hack.
            if (forceWebSearch) 'forceWebSearch': true,
            // the backend API: opaque string prepended to the system
            // prompt for this turn, honoured only when the chat's section is
            // `shell`, capped at 4 KB server-side and silently ignored
            // otherwise. This is what tells the model it has a device shell —
            // without it, asking the agent to list a directory produced advice
            // about running `ls` yourself rather than a tool call.
            if (deviceContext != null && deviceContext.isNotEmpty)
              'deviceContext': deviceContext,
          },
        )
        .map(_parseStreamLine);
  }

  /// Opens a run on the run-protocol path and yields raw frames.
  ///
  /// ## Why the agent surfaces do not use [streamCompletion]
  ///
  /// `/complete` puts the device capabilities in the system prompt as a
  /// STRING and attaches no `tools`. A model told about tools in prose emits
  /// the call template as text — the Gemma `<tool_call>` and GLM "Action:"
  /// repros were both that, not a model-quality problem. `/agent/run` attaches
  /// the eight real device tool schemas, which is what makes a tool call a
  /// tool call (the backend API, live 2026-08-04).
  ///
  /// Raw maps rather than StreamEvent: these are run-protocol frames with
  /// `run_id` and `seq`, which AgentFrame understands and the chat event
  /// vocabulary does not.
  Stream<Map<String, dynamic>> streamAgentRun({
    required String chatId,
    required String message,
    required String modelId,
    Map<String, dynamic>? scope,
    List<String> capabilities = const [],
    String? scrollback,
    String? focus,
    int? maxTurns,
  }) {
    return _client
        .stream(
          ApiConstants.AGENT_RUN,
          data: {
            'chatId': chatId,
            'message': message,
            'modelId': modelId,
            if (capabilities.isNotEmpty) 'capabilities': capabilities,
            if (scope != null) 'scope': scope,
            // What the human has actually seen. Without it the model re-runs
            // work already on screen and answers about the wrong directory.
            if (scrollback != null && scrollback.isNotEmpty)
              'scrollback': scrollback,
            // What this surface is FOR, in the agent's own terms.
            //
            // `AgentSurface.focus` existed for weeks and was read by nothing —
            // declared, carefully worded, never sent. The backend API reported that
            // Code "already tells it not to print a code block and call it
            // done"; that was wrong, and it wasted a round trip with the chat
            // team chasing a model that was never given the instruction.
            if (focus != null && focus.isNotEmpty) 'focus': focus,
            // How many rounds this surface gets before core stops the
            // run. Per-surface because the jobs differ in shape — Code
            // was hitting the default ceiling mid-build.
            // Server clamps to 50.
            if (maxTurns != null) 'maxTurns': maxTurns,
          },
        )
        .map((line) {
          try {
            final decoded = jsonDecode(line);
            // Kept, like the `[runproto] POST` line it pairs with. A run that
            // hangs shows the user "Thinking…" and nothing else, and the two
            // questions that matter — is the server still sending, and is what
            // it sends going anywhere — cannot be answered after the fact
            // without this. It logs the shape, never the content: a frame
            // carries the user's own text and their files' contents.
            if (decoded is Map<String, dynamic>) {
              debugPrint('[runproto] frame ${decoded['type']} '
                  'seq=${decoded['seq']} keys=${decoded.keys.join(",")}');
            }
            return decoded is Map<String, dynamic>
                ? decoded
                : <String, dynamic>{'type': 'error', 'message': 'bad frame'};
          } catch (_) {
            // One unparseable frame must not end the run — the rest of the
            // stream is still worth having.
            return <String, dynamic>{
              'type': 'error',
              'message': 'Unparseable frame from the server.',
            };
          }
        })
        .where(isProgressFrame);
  }

  /// Resume a truncated assistant turn. The server re-feeds the conversation
  /// (including the partial assistant message) and streams ONLY the
  /// continuation. Tokens should be appended to the existing message bubble
  /// identified by [messageId] — no new bubble is created.
  ///
  /// Spec: the backend API §4. The `start` and `done` events on this
  /// stream both carry `mode: "resume"` so callers can distinguish them
  /// from a fresh turn.
  Stream<StreamEvent> streamResume({
    required String chatId,
    required String messageId,
  }) {
    return _client
        .stream(
          ApiConstants.chatResume(chatId),
          data: {'messageId': messageId},
        )
        .map(_parseStreamLine);
  }

  StreamEvent _parseStreamLine(String line) {
    try {
      return StreamEvent.fromJson(jsonDecode(line) as Map<String, dynamic>);
    } catch (_) {
      return const StreamEvent.error(message: 'Failed to parse stream event');
    }
  }
}
