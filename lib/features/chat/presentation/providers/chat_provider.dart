import 'dart:async';
// Imported a second time under a prefix, on purpose.
//
// `core/errors/app_exception.dart` (imported below) declares its OWN
// `TimeoutException`, and Dart resolves a clash between a `dart:` import and a
// package import in favour of the package — silently, with no analyzer
// warning. So the bare name in this file means the app's class, and every
// `on TimeoutException` here was catching something `Stream.timeout` never
// throws. The visible symptom was a user staring at "TimeoutException after
// 0:05:00.000000: No stream event" (device, 2026-08-05). Use `async.` for the
// one the SDK throws.
import 'dart:async' as async;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/tool_call_leak.dart';
import 'package:cyberneurova_mobile/core/agent/device/background_runs.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/core/connectivity/connectivity_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/chat_list_cache.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/message_sources_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/model_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/agent_session_provider.dart';
import 'package:cyberneurova_mobile/core/agent/neurova_home.dart';
import 'package:cyberneurova_mobile/core/agent/local/local_chat_stream.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/local_llm_provider.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';

/// What a run that ran out of turns says.
///
/// A shared constant because the failure bubble keys off it to offer Continue
/// instead of only Retry — and retrying is the wrong move here. The budget is
/// 15 turns (the framework default; `/agent/run` forwards no override), so a
/// run that hits it has usually done real work — written files, installed
/// packages — and starting over throws that away and spends the same 15 turns
/// arriving at the same place.
const kStepLimitReason =
    'The run hit its step limit before finishing. It can carry on from where '
    'it stopped.';

/// What a run that went silent says.
///
/// Distinct from the step limit: nothing was accomplished, so there is nothing
/// to carry on from and Retry is the right offer. `/agent/run` holds the
/// connection open with a `heartbeat` every 15 seconds whether or not the run
/// is alive, so silence is the only symptom the client ever sees.
const kStalledRunReason =
    'The agent stopped responding and the run was ended. Nothing was changed '
    'on your device.';

/// The same stall, after the run had already done something to the phone.
///
/// The stall usually happens straight after a device tool reports back, so the
/// half-finished case is the common one, not the exception — a run died having
/// created a file and the bubble told the user nothing had been changed.
const kStalledRunPartialReason =
    'The agent stopped responding and the run was ended part-way through. '
    'Some steps had already run on your device — check the Shell tab to see '
    'what changed.';

/// Turns a thrown object into something worth showing a person.
///
/// The failure bubble renders this string verbatim, so whatever lands here is
/// read by the user. It used to be `e.toString()`, which put
/// "TimeoutException after 0:05:00.000000: No stream event" on screen —
/// seen on device 2026-08-05. A raw Dart exception tells the user nothing they
/// can act on and reads like a crash.
///
/// The exception type is still logged next to this call; it belongs in logcat,
/// not in the conversation.
String humanStreamError(Object e) {
  if (e is async.TimeoutException) return kStalledRunReason;
  if (e is SocketException || e is HttpException) {
    return 'Lost the connection to the agent. Check your network and try '
        'again.';
  }
  if (e is DioException) {
    return e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout
        ? 'Could not reach the agent. Check your network and try again.'
        : 'The agent returned an error. Try again.';
  }
  return 'Something went wrong on the way to the agent. Try again.';
}

/// One-shot transfer: holds a message typed on the New Chat welcome screen
/// while we navigate to the freshly-created chat. The detail screen reads
/// + clears this on first build so the user's prompt isn't lost.
final pendingFirstMessageProvider =
    StateProvider.autoDispose<String?>((_) => null);

/// Per-turn token usage from the most recent assistant reply.
/// `null` when no completion has finished yet. Wired from the stream
/// `usage` event. UI can show this in a dev menu or under the message.
class TurnUsage {
  const TurnUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
}

/// Per-turn usage — kept long-lived because the Usage screen reads it
/// from anywhere, including after navigating away from the chat.
final lastTurnUsageProvider = StateProvider<TurnUsage?>((_) => null);

/// True while a chat stream is actively running. Mirrors the typing indicator
/// state and lets other widgets (top bar, drawer) react to it.
final streamRunningProvider = StateProvider<bool>((_) => false);

/// Payload for the stale-chat-403 recovery flow: when a send hits 403
/// because the active chat doesn't belong to the user, the screen reads
/// this, creates a fresh chat, navigates, and replays the original send.
class StaleSendRecovery {
  const StaleSendRecovery({
    required this.originalText,
    this.attachments,
  });
  final String originalText;
  final List<Map<String, dynamic>>? attachments;
}

final lastSendStaleChatErrorProvider =
    StateProvider<StaleSendRecovery?>((_) => null);

/// Latest error message from a failed `/complete/resume` call.
/// Read by the chat screen to surface a toast — kept out of the message
/// list since the original truncated bubble is still useful.
/// Set to `null` after the screen consumes it.
final lastResumeErrorProvider = StateProvider<String?>((_) => null);

/// Latest auto-web-search status emitted by the active chat stream.
/// `null` = no search active. Cleared when stream ends or a new send starts.
/// Surfaced by `_TypingIndicator` so the user sees "Searching the web…"
/// instead of generic dots when chat-team's auto-search kicks in.
class WebSearchStatus {
  const WebSearchStatus({required this.phase, this.query, this.resultCount});

  /// One of: "searching" | "searched" | "no-results"
  final String phase;
  final String? query;
  final int? resultCount;
}

final activeWebSearchProvider = StateProvider<WebSearchStatus?>((_) => null);

/// Latest agentic tool status emitted by the active chat stream
/// (inbox/025). `status: 'tool-running'` events carry a human-readable
/// `query` ("Reading main.py") shown live by `_TypingIndicator`;
/// `status: 'tool-done'` clears it. Lifecycle mirrors
/// [activeWebSearchProvider] exactly: cleared when the stream ends, a new
/// send starts, or the chat notifier is disposed.
class ToolStatus {
  const ToolStatus({this.query});
  final String? query;
}

final activeToolStatusProvider = StateProvider<ToolStatus?>((_) => null);

/// When true, the next send prepends "search the web for " to the user's
/// message so chat-team's explicit-search regex
/// (`\bsearch\s+(?:the\s+)?web\b`) catches it and forces the auto-search
/// path — bypassing the conservative auto-detection heuristic.
///
/// Per-chat (family) so flipping it on in one chat doesn't leak into
/// other chats. Mid-test feedback: this toggle is the difference between
/// "search just doesn't work for me" and a user explicitly opting in.
final webSearchToggleProvider =
    NotifierProviderFamily<WebSearchToggleNotifier, bool, String>(
  WebSearchToggleNotifier.new,
);

class WebSearchToggleNotifier extends FamilyNotifier<bool, String> {
  @override
  bool build(String chatId) => false;
  void toggle() => state = !state;
  void off() => state = false;
}

/// Chat ids that have 403'd this session and should NOT be picked again
/// by [ChatBootstrapScreen]. Without this, the bootstrap → chat-detail →
/// 403 → goNamed('chats') → bootstrap chain would loop forever on the
/// same `chats.first.id` (a stale chat from a prior OAuth session, or a
/// chat whose freshness-race fallback failed because chatListProvider
/// was mid-rebuild). Cleared on app cold-start.
final blacklistedChatsProvider =
    NotifierProvider<BlacklistedChatsNotifier, Set<String>>(
  BlacklistedChatsNotifier.new,
);

class BlacklistedChatsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void add(String id) {
    if (id.isEmpty || state.contains(id)) return;
    state = {...state, id};
  }
}

/// Drawer chat-list multi-selection state.
///
/// Empty set = normal browse mode (tap navigates).
/// Non-empty set = selection mode (tap toggles, long-press is a no-op
/// since selection is already active, top action bar shows up).
///
/// Lives at the provider layer instead of inside the drawer widget so
/// the action bar (Delete / Add to project) can read the selection
/// without tunneling it through three layers of build() callbacks.
final selectedChatsProvider =
    NotifierProvider<SelectedChatsNotifier, Set<String>>(
  SelectedChatsNotifier.new,
);

class SelectedChatsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void toggle(String id) {
    if (id.isEmpty) return;
    final next = {...state};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = next;
  }

  void clear() => state = const {};
  void selectAll(Iterable<String> ids) => state = {
        for (final id in ids)
          if (id.isNotEmpty) id
      };
}

/// Set of assistant message IDs whose `done` event carried `truncated: true`
/// (chat-team inbox/014). The Continue button watches this set instead of
/// running a fence heuristic — precise signal, no false positives.
///
/// Cleared on app cold start. We never persist this: if the server's
/// response is reloaded from history (`getChatWithMessages`) the user
/// can no longer resume from it anyway — resume is in-session only.
final truncatedMessagesProvider =
    NotifierProvider<TruncatedMessagesNotifier, Set<String>>(
  TruncatedMessagesNotifier.new,
);

class TruncatedMessagesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void mark(String messageId) {
    if (messageId.isEmpty) return;
    state = {...state, messageId};
  }

  void clear(String messageId) {
    if (!state.contains(messageId)) return;
    final next = {...state}..remove(messageId);
    state = next;
  }
}

// List of chats with cursor-based pagination
/// The plain conversations — everything NOT owned by an agent surface.
///
/// Agent sessions are ordinary chats carrying a `section` tag, which keeps one
/// store and one sync path. The cost is that any surface listing chats shows
/// Console, Code and Research sessions alongside real conversations unless it
/// says otherwise: a Console session named after a shell command was appearing
/// in the drawer's Recents next to the user's actual chats.
///
/// Each agent surface filters to its own section; this is the other half —
/// the chat surfaces filter to theirs. Unknown sections count as agent-owned
/// rather than plain, so a section added on the server does not leak into the
/// drawer before the app knows what it is.
final plainChatListProvider = Provider<AsyncValue<List<ChatModel>>>((ref) {
  return ref.watch(chatListProvider).whenData(
        (all) => all
            .where((c) => c.section == AppConstants.sectionChat)
            .toList(growable: false),
      );
});

final chatListProvider =
    AsyncNotifierProvider<ChatListNotifier, List<ChatModel>>(
  ChatListNotifier.new,
);

/// True when the visible chat list came from disk because the fetch failed.
///
/// The distinction matters: showing yesterday's titles silently would be a
/// lie, and showing an error page when we HAVE the titles is needlessly
/// hostile. This lets the UI say "saved copy" and offer a retry.
final chatListIsStaleProvider = StateProvider<bool>((_) => false);

class ChatListNotifier extends AsyncNotifier<List<ChatModel>> {
  /// The sections the server splits chats into, per its contract (reply to
  /// outbox 064): `chat` is the day-to-day list that syncs with web and
  /// desktop; the rest are agent surfaces. Rows written before the field
  /// existed have no section and count as `chat`.
  static const _sections = ['chat', 'code', 'research', 'shell'];

  /// One cursor per section, because the server now paginates within each.
  final Map<String, String?> _cursors = {};

  /// Sections that have no further pages, so we stop asking.
  final Set<String> _exhausted = {};

  bool _hasMore = true;
  bool _loadingMore = false;

  String get _userId => ref.read(authProvider).valueOrNull?.id ?? '';

  @override
  Future<List<ChatModel>> build() async {
    // Watch the currently-authenticated user id — when it changes
    // (login, logout, account switch) Riverpod rebuilds this notifier
    // and refetches from scratch. Without this, a previous user's chat
    // list persisted across sessions and the bootstrap screen would
    // route the new user to a chat they don't own → 403 on first send.
    ref.watch(authProvider.select((value) => value.valueOrNull?.id));
    _cursors.clear();
    _exhausted.clear();
    _hasMore = true;

    // Paint the cached list FIRST, then refresh behind it.
    //
    // Waiting for the network before showing anything is why the app looked
    // like it hung on a slow connection: the chats were on disk the whole
    // time and we sat on a skeleton anyway. Serving them immediately and
    // reconciling when the response lands is the difference between "loading"
    // and "loaded, updating".
    final cached = await ChatListCache.load(_userId);
    if (cached != null && cached.isNotEmpty) {
      unawaited(_refreshBehind());
      return cached;
    }

    try {
      final chats = await _fetch();
      ref.read(chatListIsStaleProvider.notifier).state = false;
      // Fire and forget — persisting must never delay the UI.
      unawaited(ChatListCache.save(_userId, chats));
      return chats;
    } catch (e) {
      // Prefer stale truth over an error page. The chats exist; we just could
      // not reach the server. Falling back keeps the app navigable offline and
      // turns a dead end into a notice.
      final cached = await ChatListCache.load(_userId);
      if (cached != null && cached.isNotEmpty) {
        ref.read(chatListIsStaleProvider.notifier).state = true;
        // Pagination is meaningless against a cache — asking for page 2 of a
        // list we did not fetch would hit the network we already know is down.
        _hasMore = false;
        return cached;
      }
      rethrow;
    }
  }

  /// Fetches one page of EACH section and merges them.
  ///
  /// One list still backs every surface — Recents, Search, and the Code,
  /// Shell and Research session lists all read this provider and filter it by
  /// section. That is why "just add `section=chat`" would have been wrong: it
  /// fixes Recents by emptying the other four.
  ///
  /// Asking per section fixes all five instead. The page limit used to be
  /// spent across every section at once, so a day of Console testing — 14
  /// shell sessions and 4 research ones inside the newest 20 rows — left the
  /// owner's Recents showing two chats and his real history unreachable. Now
  /// each section gets its own page and none can evict another.
  ///
  /// Deduped by id because a server that does not know the parameter would
  /// answer all four requests with the same unfiltered list, and four copies
  /// of every row is a worse bug than the one being fixed.
  Future<List<ChatModel>> _fetch() async {
    final repo = ref.read(chatRepositoryProvider);
    final wanted = _sections.where((s) => !_exhausted.contains(s)).toList();

    final pages = await Future.wait([
      for (final s in wanted) repo.listChats(cursor: _cursors[s], section: s),
    ]);

    final merged = <ChatModel>[];
    final seen = <String>{};
    for (var i = 0; i < wanted.length; i++) {
      final section = wanted[i];
      final page = pages[i];
      _cursors[section] = page.nextCursor;
      // A cursor you do not have cannot be advanced. The server answers
      // `hasMore: true` without always sending `nextCursor`, and trusting the
      // flag alone re-requests page one for ever — which is exactly what
      // shipped the moment pagination was wired up: the drawer filled with
      // duplicate rows. No documented contract for these fields yet (outbox
      // 061), so the client refuses to page without one.
      if (!(page.hasMore && page.nextCursor != null)) _exhausted.add(section);
      for (final c in page.chats) {
        if (seen.add(c.id)) merged.add(c);
      }
    }
    _hasMore = _exhausted.length < _sections.length;

    // Interleaved sections have to be re-sorted: newest first, matching what
    // a single unfiltered page used to arrive in.
    merged.sort((a, b) {
      final at = a.updatedAt ?? a.createdAt;
      final bt = b.updatedAt ?? b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return merged;
  }

  /// Re-fetches while the cached list is already on screen.
  ///
  /// Failure here is deliberately quiet: the user is looking at real data, and
  /// interrupting that with an error for a refresh they did not ask for would
  /// be worse than showing slightly old titles. The stale flag says so
  /// instead, and offers a retry.
  Future<void> _refreshBehind() async {
    try {
      _cursors.clear();
      _exhausted.clear();
      _hasMore = true;
      final fresh = await _fetch();
      ref.read(chatListIsStaleProvider.notifier).state = false;
      unawaited(ChatListCache.save(_userId, fresh));
      state = AsyncData(fresh);
    } catch (_) {
      ref.read(chatListIsStaleProvider.notifier).state = true;
      // Pagination against a cache would hit the network we just failed on.
      _hasMore = false;
    }
  }

  Future<void> loadMore() async {
    // Sahachiel: re-entrancy guard. Without it a fast scroll fires loadMore
    // twice before the first await resolves; both GET the same _cursor (a
    // duplicate page), then the second response overwrites _cursor and the
    // page in between is skipped forever.
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final more = await _fetch();
      // Read the list AFTER the fetch, not before. A page GET takes seconds
      // on a bad connection, and the list is mutated from elsewhere the whole
      // time: createChat prepends, deleteChat removes, titleFromFirstMessage
      // rewrites a row. Appending onto a snapshot taken before the await
      // silently reinstates all of it — delete a chat mid-scroll and it comes
      // back, start a new one and it vanishes from Recents.
      final current = state.valueOrNull ?? [];
      // Never append a chat that is already on screen. The belt to the
      // cursor check's braces: whatever the server does with `startingAfter`,
      // the same conversation must not appear twice in the drawer.
      final seen = {for (final c in current) c.id};
      final fresh = [
        for (final c in more)
          if (!seen.contains(c.id)) c
      ];
      // A page that adds nothing new means we are re-reading one we already
      // have. Stop, rather than ask again on every scroll for ever.
      if (fresh.isEmpty) {
        _hasMore = false;
        return;
      }
      state = AsyncData([...current, ...fresh]);
    } finally {
      _loadingMore = false;
    }
  }

  /// [section] tags the chat as a plain chat, a Code workspace session, or a
  /// Research session ([AppConstants.sectionChat] / `sectionCode` /
  /// `sectionResearch`). The Agents surfaces filter on it.
  Future<ChatModel> createChat({
    String? title,
    String section = AppConstants.sectionChat,
  }) async {
    final repo = ref.read(chatRepositoryProvider);
    final chat = await repo.createChat(title: title, section: section);
    // The backend currently drops `section` (see SectionStore) — remember it
    // here so the workspace lists aren't empty. Harmless once it round-trips.
    final current = state.valueOrNull ?? [];
    state = AsyncData([chat, ...current]);
    return chat;
  }

  /// The ONE new-chat entry point every trigger should use (drawer bottom
  /// bar, chat app-bar +, bootstrap, post-delete navigation): reuses an
  /// existing empty chat — `messageCount == 0` and not in
  /// [blacklistedChatsProvider] — instead of minting another record, so
  /// repeated "New chat" taps without sending can't pile blank "New chat"
  /// rows into Recents. Creates a fresh chat only when no reusable empty
  /// chat exists. Same logic ChatBootstrapScreen has always used on cold
  /// launch, factored here so all call sites agree.
  Future<ChatModel> reuseOrCreateEmptyChat() async {
    final chats = await future;
    final blocked = ref.read(blacklistedChatsProvider);
    for (final c in chats) {
      if (blocked.contains(c.id)) continue;
      // Plain conversations only. An empty Console, Code or Research session
      // is empty in exactly the same way, so this used to hand one back and
      // the app opened INSIDE an agent surface on launch — the owner landed on
      // a screen titled "Console" without ever going through Agents, which
      // reads as the app having moved on its own. Those sessions belong to
      // their surfaces and are reached from there.
      if (c.section.isNotEmpty && c.section != AppConstants.sectionChat) {
        continue;
      }
      if (c.messageCount == 0) return c;
    }
    return createChat();
  }

  /// Names a session from its first message, when nothing else will.
  ///
  /// Local only, now that the server names agent sessions itself.
  ///
  /// It used to PATCH as well, because agent turns are not written to
  /// `/chat/:id/messages` (outbox 046) so the server never saw an exchange to
  /// title from — leaving a Shell list of five rows all called "New Chat". It
  /// titles from the first user message on `/agent/run` as of its 064 reply,
  /// and two writers of one field is what made the phone and the web disagree
  /// about the same row in the first place. So the durable name is theirs.
  ///
  /// The optimistic local rename stays: the row should read correctly the
  /// moment the run starts, not on the next list fetch. Their derivation may
  /// differ slightly from ours, in which case the row settles to theirs when
  /// the list refreshes — cosmetic, and better than "New chat" for a minute.
  ///
  /// Updates in place rather than invalidating: `isAgentSessionProvider`
  /// watches this list, and dropping it to loading mid-run would take the
  /// workspace — and the device tools executing in that run — down with it.
  Future<void> titleFromFirstMessage(String chatId, String message) async {
    final current = state.valueOrNull ?? const <ChatModel>[];
    final chat = current.firstWhere(
      (c) => c.id == chatId,
      orElse: () => const ChatModel(),
    );
    if (chat.id.isEmpty) return;
    if (!isPlaceholderChatTitle(chat.title)) return;

    // A greeting or filler opener ("hey", "good morning", "test") is not what
    // the session is about — leave the title a placeholder so the NEXT,
    // substantive message names it (this method fires per send and no-ops once
    // a real title is set).
    if (isGreetingOrLowSignal(message)) return;

    final title = titleFromMessage(message);
    if (title.isEmpty) return;

    state = AsyncData([
      for (final c in current) c.id == chatId ? c.copyWith(title: title) : c,
    ]);
  }

  Future<void> deleteChat(String id) async {
    await ref.read(chatRepositoryProvider).deleteChat(id);
    // Kill the shell too, if this chat had one.
    //
    // The workspace registry deliberately outlives the widget tree so a
    // session survives navigation — which meant deleting a Console chat left
    // its PTY (and, under PRoot, the whole guest process tree) running with
    // nothing able to reach it. An orphaned shell holding a rootfs open is a
    // real leak, not a tidiness issue.
    await ref.read(shellWorkspaceRegistryProvider)?.kill(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((c) => c.id != id).toList());
  }
}

// Per-chat message list + streaming state.
// autoDispose so each chat opened doesn't sit in memory forever — when the
// user navigates away from a chat detail, its messages drop. Re-opening the
// same chat re-fetches (cheap; we paginate). Without this, opening N chats
// in a session kept N message lists in memory until app kill.
final chatDetailProvider = AsyncNotifierProvider.autoDispose.family<
    ChatDetailNotifier,
    ({ChatModel chat, List<MessageModel> messages}),
    String>(
  ChatDetailNotifier.new,
);

class ChatDetailNotifier extends AutoDisposeFamilyAsyncNotifier<
    ({ChatModel chat, List<MessageModel> messages}), String> {
  // Sahachiel: this autoDispose family notifier can be torn down (drawer nav,
  // + New chat, stale-403 recovery) while a stream is still draining. Touching
  // ref/state after dispose throws StateError. _disposed lets the stream loop
  // bail before mutating a dead notifier; _cancelRequested powers the Stop button.
  bool _disposed = false;
  bool _cancelRequested = false;

  /// Converts the stream's `status` events into agent-transcript frames.
  /// Created per send so its synthetic call ids don't collide across turns.
  AgentStatusBridge? _agentBridge;

  /// User tapped Stop — the active stream loop breaks on its next event,
  /// which cancels the underlying HTTP subscription (closing the socket).
  void stopStreaming() => _cancelRequested = true;

  /// Keeps the process alive for as long as a turn is in flight.
  ///
  /// A phone user backgrounds the app while the model is answering — that is
  /// ordinary behaviour, not misuse — and without this the process can be
  /// reclaimed mid-stream and the answer is simply lost.
  BackgroundRun? _bgRun;

  /// Streams a run-protocol turn and folds its frames into both transcripts.
  ///
  /// Two consumers, one stream. [AgentSession] owns the tool cards and — the
  /// point of all this — actually RUNS the device calls, posting results back
  /// through the outbox. The chat transcript owns the prose the user reads.
  /// Feeding both from one pass is what keeps the bubble and the cards
  /// describing the same turn.
  Future<void> _streamAgentRun({
    required String text,
    required String assistantId,
    required List<MessageModel> userMessages,
  }) async {
    final repo = ref.read(chatRepositoryProvider);
    final agentNotifier = ref.read(agentSessionProvider(arg).notifier);
    final caps = ref.read(deviceCapabilitiesProvider);
    final scope = ref.read(sessionScopeProvider(arg));

    _setStreaming(true, label: 'Working');
    ref.read(activeWebSearchProvider.notifier).state = null;
    ref.read(activeToolStatusProvider.notifier).state = null;

    // Write the user's turn down BEFORE the run, not only after it.
    //
    // The save at the end of this method is the only one there used to be, so
    // a run that never reached the end took the user's message with it.
    // Verified on device 2026-08-05: asked for something, force-stopped the
    // app mid-run, reopened — the two completed turns came back and the
    // interrupted one had vanished without trace. Nothing told them it had
    // been lost, and they had no copy of what they typed.
    //
    // The assistant placeholder is empty at this point and `_persistLocally`
    // skips empty content, so this stores the question and nothing else.
    unawaited(_persistLocally());

    String? streamError;
    var accumulated = '';
    var lastSeq = -1;

    // Whether this run's file work happened in a server workspace instead of
    // on the phone. See _serverWorkspaceNote for why that has to be said out
    // loud rather than left for the user to discover with `ls`.
    var serverSideWork = false;

    // A refused call still produces a `workspace_change`, so without this the
    // note below would claim files were written on the server in the very turn
    // that just told the user nothing was changed.
    var replyWasRefusedCall = false;

    // Whether anything in this run executed on the phone. The server emits a
    // `workspace_change` for a DEVICE write too, so without this the note
    // below claimed a file had gone to a server workspace in the very run that
    // wrote it to the handset — a confident, wrong answer, which is worse than
    // saying nothing.
    var deviceRan = false;

    /// Whether the run called ANY tool. See [_unsourcedResearchNote].
    var anyToolCall = false;

    /// How many sources the server's pre-search actually fetched, and which.
    /// Zero means it did not fetch — either it never ran, or SearXNG came back
    /// empty. Both are "the model answered from memory" as far as the reader
    /// is concerned, and both deserve the note.
    var searchedCount = 0;
    var searchedSources = const <String>[];

    /// Text accumulated from `partial` deltas for the message in flight.
    var streamed = '';

    try {
      final stream = repo.streamAgentRun(
        chatId: arg,
        message: _withPriorTurns(text),
        modelId: ref.read(effectiveModelProvider),
        capabilities: [for (final c in caps.present) c.name],
        // ALWAYS sent, including when empty. An empty scope is not "no
        // opinion" — it is our narrowest setting, meaning the device itself
        // and nothing else. Omitting it left the server with no scope to
        // enforce, which is why an out-of-scope target was never refused:
        // nothing had told the server what in-scope meant.
        scope: scope.toJson(),
        // What the human has actually seen in the pane. Without it the model
        // re-runs work already on screen and answers about the wrong cwd.
        scrollback: _recentScrollback(),
        focus: ref.read(agentSurfaceProvider(arg))?.focus,
        // Per-surface round budget (outbox 054). Code needs many more than
        // Console: building something is a long chain, and a terminal the
        // user is watching is not.
        maxTurns: ref.read(agentSurfaceProvider(arg))?.maxTurns,
      );

      await for (final json in stream.timeout(const Duration(minutes: 5))) {
        if (_cancelRequested || _disposed) break;

        // Dedupe by highest seq, per 029: a reconnect replays frames and the
        // transcript must not double-apply them.
        final seq = json['seq'];
        if (seq is int) {
          if (seq <= lastSeq) continue;
          lastSeq = seq;
        }

        final frame = AgentFrame.tryParse(json);
        if (frame != null) {
          agentNotifier.apply(frame, runId: json['run_id'] as String?);
        }

        // A `workspace_change` is proof a file op landed somewhere. It is
        // server-side unless the frame says a device executed it.
        //
        // `tool_call` does carry `executor` — confirmed on the wire 2026-08-05
        // (`keys=type,run_id,call_id,tool,executor,input,seq`). An older
        // comment here said no frame carried it at all, which made `deviceRan`
        // look like dead code it is not: the stall message depends on it to
        // avoid telling the user nothing was touched when something was.
        if (json['type'] == 'tool_call') {
          anyToolCall = true;
          if (json['executor'] == 'device') deviceRan = true;
        }

        // Did the server actually fetch anything for this answer?
        //
        // We used to infer it from the absence of a `tool_call`, which was
        // wrong the moment the pre-search moved server-side: it emits no tool
        // call, so a properly sourced answer got labelled as recalled. Core
        // now says so directly (chat-team reply to outbox 063) and only when
        // results really came back, so this is the signal rather than a guess.
        if (json['type'] == 'system' &&
            json['subtype'] == 'web_search_results') {
          final n = json['count'];
          if (n is num && n > 0) {
            searchedCount = n.toInt();
            final raw = json['sources'];
            if (raw is List) {
              searchedSources = [
                for (final s in raw)
                  if (s is String && s.isNotEmpty) s
              ];
            }
          }
        }
        if (json['type'] == 'workspace_change' &&
            json['executor'] != 'device') {
          serverSideWork = true;
        }

        // The prose half.
        //
        // A `partial: true` assistant frame is a DELTA — usually a single
        // token. I originally recorded these as carrying the whole reply so
        // far and replaced the bubble on each one, which is why streaming
        // looked like single words flickering in place and then the entire
        // text appearing at the end: the last `result` frame carries the
        // complete answer, so only that one ever looked right.
        //
        // Everything else — a complete `assistant` message, or `result` — is
        // the whole thing and replaces.
        final text = _textFromFrame(json);
        if (text != null && text.isNotEmpty) {
          if (json['partial'] == true) {
            streamed += text;
            _showAssistant(assistantId, streamed, schedule: true);
            continue;
          }
          streamed = '';
          // A refused tool call comes back as the raw call template inside a
          // frame flagged success, so nothing upstream marks it as a failure.
          // Never render that; say what happened instead.
          final thought = stripSystemDirectives(stripThinkTags(text));
          final safe = stripToolCallTemplates(thought);
          replyWasRefusedCall = safe.isOnlyToolCall;
          accumulated = _render(safe, thought);
          _replaceAssistant(assistantId, accumulated);
        }

        if (json['type'] == 'error') {
          streamError = _failureReason(json);
        }
        if (json['type'] == 'result' ||
            json['type'] == 'done' ||
            json['type'] == 'run_finished') {
          // `result` carries the final text and is the real terminator; `done`
          // may not arrive at all.
          if (json['is_error'] == true) {
            streamError = _failureReason(json);
          }
          break;
        }
      }
    } on async.TimeoutException {
      debugPrint('[runproto] run ended: idle timeout (deviceRan=$deviceRan)');
      // Only promise nothing happened when nothing did. The first build of
      // this said "Nothing was changed on your device" on a run that had
      // already created a file on the handset before going quiet — a
      // confident, wrong answer about the user's own storage.
      streamError = deviceRan ? kStalledRunPartialReason : kStalledRunReason;
    } catch (e) {
      debugPrint('[runproto] run ended: ${e.runtimeType}');
      streamError = humanStreamError(e);
    }

    _agentFlush?.cancel();
    _agentFlush = null;

    // A run that ended on deltas alone never produced a whole-message frame,
    // so `accumulated` would be empty and the reply would vanish on finish.
    // `result` normally supplies it; this covers the run that stops early.
    if (accumulated.isEmpty && streamed.isNotEmpty) {
      accumulated = _renderable(streamed);
      _replaceAssistant(assistantId, accumulated);
    }

    // A failed run that had already produced prose loses it: _finishStream
    // drops the assistant placeholder to make room for the failure bubble. If
    // the model got half an answer out before dying, that half is worth
    // keeping — carry it into the failure text rather than throwing it away.
    if (streamError != null && accumulated.trim().isNotEmpty) {
      streamError = '$streamError\n\n$accumulated';
    }

    if (_disposed) return;
    if (serverSideWork &&
        !deviceRan &&
        !replyWasRefusedCall &&
        streamError == null) {
      accumulated = '$accumulated${_serverWorkspaceNote()}';
      _replaceAssistant(assistantId, accumulated);
    }
    // Keyed on what the server reports fetching, not on tool calls — a
    // research answer can be perfectly sourced without a single tool_call,
    // and labelling that as recalled is the mistake this used to make.
    // A device tool still counts: a run that fetched a page itself is sourced
    // whatever the pre-search did.
    // The other half of 063: when the server DID fetch, say what it read.
    //
    // Only when the model has not already listed them — it usually writes its
    // own "Sources:" block, and printing the same URLs twice under one answer
    // reads as a bug. This is the fallback for the case the 057 report was
    // really about: a confident answer with no way to check it.
    if (searchedCount > 0 && searchedSources.isNotEmpty && !_disposed) {
      // Expose the fetched sources as a tappable "Sources" chip under the
      // answer (see _MessageActions), reference-style — keyed by the same id the
      // bubble renders under, and persisted so it survives reload.
      ref
          .read(messageSourcesProvider.notifier)
          .set(assistantId, searchedSources);
    }
    if (searchedCount > 0 &&
        searchedSources.isNotEmpty &&
        streamError == null &&
        accumulated.trim().isNotEmpty &&
        !searchedSources.any(accumulated.contains)) {
      accumulated = '$accumulated${_fetchedSourcesNote(searchedSources)}';
      _replaceAssistant(assistantId, accumulated);
    }
    if (searchedCount == 0 &&
        !anyToolCall &&
        streamError == null &&
        accumulated.trim().isNotEmpty &&
        ref.read(agentSurfaceProvider(arg)) == AgentSurface.research) {
      accumulated = '$accumulated${_unsourcedResearchNote()}';
      _replaceAssistant(assistantId, accumulated);
    }
    // Say that it was stopped, when it was.
    //
    // Cancelling worked but left no trace: the turn simply ended with nothing
    // where a reply would be, so "I stopped it" and "it failed silently" looked
    // identical. Verified on device — a cancelled `sleep 45` produced a user
    // bubble and then blank space.
    if (_cancelRequested && accumulated.trim().isEmpty) {
      accumulated = '_Stopped._';
      _replaceAssistant(assistantId, accumulated);
    }

    // Retry replays what the USER asked for. This used to pass `accumulated`,
    // so tapping Retry after a failed run re-sent the model's own half-written
    // answer as if the user had typed it.
    _finishStream(streamError, assistantId, text);
    unawaited(_persistLocally());
  }


  /// Fills in turns the server does not have.
  ///
  /// Agent-run turns are not written to `/chat/:id/messages`, so reopening a
  /// Console, Code or Research session brought its tool cards back and left
  /// the conversation blank — a wall of actions with no words around them. The
  /// owner reported it twice. Until the server stores them, the phone keeps
  /// its own copy under `~/.neurova/chats` and it is merged in here.
  ///
  /// The server wins on any id it knows: it is authoritative for plain chats,
  /// and this must never resurrect a turn the user deleted there.
  Future<List<MessageModel>> _withLocal(List<MessageModel> fromServer) async {
    try {
      final store = await ref.read(localChatStoreProvider.future);
      final stored = await store.load(arg);
      if (stored.isEmpty) return fromServer;

      final known = {for (final m in fromServer) m.id};
      final merged = [
        ...fromServer,
        for (final t in stored)
          if (!known.contains(t.id))
            MessageModel(
              id: t.id,
              chatId: arg,
              role: t.role,
              content: t.content,
              createdAt: t.createdAt,
            ),
      ]..sort((a, b) => (a.createdAt ?? DateTime(0))
          .compareTo(b.createdAt ?? DateTime(0)));
      return merged;
    } catch (_) {
      // Local history is a convenience. Never let it stop a chat opening.
      return fromServer;
    }
  }

  /// Writes this conversation to `~/.neurova/chats` so it survives the app
  /// being killed. Only for agent sessions — a plain chat is already on the
  /// server, and duplicating it would mean two sources of truth to reconcile.
  Future<void> _persistLocally() async {
    if (ref.read(agentSurfaceProvider(arg)) == null) return;
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final store = await ref.read(localChatStoreProvider.future);
      await store.save(arg, [
        for (final m in current.messages)
          if (!m.isError && m.content.trim().isNotEmpty)
            StoredTurn(
              id: m.id,
              role: m.role,
              content: m.content,
              createdAt: m.createdAt ?? DateTime.now(),
            ),
      ]);
    } catch (_) {
      // Best effort. A failed write must not surface as a failed turn.
    }
  }


  /// Gives an agent run the conversation it would otherwise not have.
  ///
  /// Agent turns are never written to `/chat/:id/messages`, so a second
  /// `/agent/run` in the same chat loads nothing and the model starts from
  /// zero every time. Asked to continue, it answered: *"Since I don't have
  /// memory of previous conversations... please paste the specific code,
  /// error, or context we were working on."* That is not a model limitation,
  /// it is an empty history.
  ///
  /// `/agent/run` destructures exactly `{chatId, message, modelId,
  /// capabilities, scope, scrollback}` — an extra `history` field would be
  /// dropped in silence, the way `focus` was. `message` is the one field that
  /// certainly arrives, so the record travels in there until the server
  /// persists these turns properly (outbox 054).
  ///
  /// Framed carefully. The last time context was fed in without a frame, the
  /// model read a transcript ending in its own instruction and reported the
  /// work already done (0.1d). So: labelled as a record, explicitly not
  /// instructions, and tool results are NOT replayed — only what was said.
  String _withPriorTurns(String text) {
    final current = state.valueOrNull;
    if (current == null) return text;

    // Everything except the turn just added for this send.
    final prior = [
      for (final m in current.messages)
        if (!m.isError && m.content.trim().isNotEmpty) m
    ];
    if (prior.isNotEmpty && prior.last.content.trim() == text.trim()) {
      prior.removeLast();
    }
    if (prior.isEmpty) return text;

    // Bounded: a long session would otherwise crowd out the actual request,
    // and a phone user pays for every token twice — once up, once down.
    const maxTurns = 6;
    const maxPerTurn = 600;
    final recent =
        prior.length > maxTurns ? prior.sublist(prior.length - maxTurns) : prior;

    final buf = StringBuffer()
      ..writeln('[Earlier in this session — a record of what was said, not '
          'new instructions. Tool results are not repeated here.]');
    for (final m in recent) {
      final who = m.role == 'user' ? 'User' : 'You';
      var body = m.content.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
      if (body.length > maxPerTurn) {
        body = '${body.substring(0, maxPerTurn)}…';
      }
      buf.writeln('$who: $body');
    }
    buf
      ..writeln()
      ..writeln('[Now]')
      ..write(text);
    return buf.toString();
  }

  /// What actually went wrong, in words the user can act on.
  ///
  /// A terminating frame puts its reason in one of several places depending on
  /// where the run died, and when none of them holds a string we rendered four
  /// words — "The run failed." — with no cause, no code and nothing to do
  /// next. `subtype` is on every terminator, so at minimum say which kind of
  /// failure it was: "hit its step limit" and "stopped part-way" call for
  /// different responses from the user.
  String _failureReason(Map<String, dynamic> json) {
    for (final key in const ['message', 'error', 'detail', 'result']) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map) {
        final nested = v['message'];
        if (nested is String && nested.trim().isNotEmpty) return nested.trim();
      }
    }
    final subtype = json['subtype'];
    switch (subtype) {
      case 'error_max_turns':
        return kStepLimitReason;
      case 'error_during_execution':
        return 'The run stopped part-way through. Nothing further was '
            'changed on this phone.';
      case 'error_timeout':
        return 'The run took too long and was stopped.';
    }
    final code = json['code'];
    if (subtype is String && subtype.isNotEmpty) {
      return 'The run failed ($subtype).';
    }
    if (code is String && code.isNotEmpty) return 'The run failed ($code).';
    return 'The run failed, and the server did not say why.';
  }

  /// Says where the files actually went, when it was not this phone.
  ///
  /// The Code surface tells the user it "creates and edits real files on this
  /// phone", and the model is told to write them rather than describe them.
  /// On the deployed run protocol those writes land in a server container:
  /// `container_acquired` with a `/workspace` cwd, and no frame carries an
  /// `executor` field at all (outbox 043).
  ///
  /// That is the owner's original complaint one layer down — *"it says it did
  /// but when i go to the shell and ls nothing is there"* — and this time the
  /// work genuinely happened, just not where the user was told to look. Until
  /// device routing lands, saying so is the difference between a limitation
  /// and a lie. When it does land the frames will carry `executor: device` and
  /// this stops appearing on its own.
  String _serverWorkspaceNote() {
    final surface = ref.read(agentSurfaceProvider(arg));
    final where = surface == AgentSurface.code ? 'project' : 'files';
    // Both halves of the Android sentence are meaningless without a device
    // shell: there is no shell for them to fail to show up in, and "still
    // being wired up" promises something iOS will never allow. What the
    // reader needs is the same fact — these are not on your phone — said in
    // terms that are true where they are standing.
    if (!PlatformFlags.hasDeviceShell) {
      return '\n\n---\n_These $where live in a workspace on CyberNeurova’s '
          'servers, not on this device. Ask for their contents if you need '
          'them here._';
    }
    return '\n\n---\n_These $where were written in a workspace on '
        'CyberNeurova’s servers, not on this phone — so they will '
        'not show up in your shell. Running the work on your own device is '
        'still being wired up._';
  }

  /// Says when a Research answer was recalled rather than looked up.
  ///
  /// Research promises the user, in its own words on its own empty state,
  /// *"Cites what it actually read, not what it recalls"*. Verified on device
  /// 2026-08-05: "what is the latest stable version of curl" returned an answer
  /// three seconds after send with **zero `tool_call` frames** — nothing was
  /// fetched — and ended with a "Sources:" heading and a styled link reading
  /// "Curl Official Website". The version and date under it were both wrong.
  ///
  /// A fabricated citation is worse than no citation: the whole point of this
  /// surface is findings the user can check, and a source line is exactly the
  /// thing they would check it by. The model was told to cite what it fetched
  /// — the instruction is in `AgentSurface.research.focus` and does reach it —
  /// and ignored it, which we cannot fix from here.
  ///
  /// What we can do is not let the app corroborate it. Zero tool calls is an
  /// unambiguous fact about the run, so it is safe to state without guessing
  /// at which tools count as a fetch.
  /// What the server actually fetched for this turn.
  ///
  /// Capped: a ten-source sweep under a three-line answer buries it. Five is
  /// enough to show the answer is checkable, which is the whole point.
  String _fetchedSourcesNote(List<String> sources) {
    final shown = sources.take(5).toList();
    final more = sources.length - shown.length;
    final lines = [for (final s in shown) '- $s'].join('\n');
    final tail = more > 0 ? '\n_and $more more_' : '';
    return '\n\n---\n**Fetched for this answer**\n$lines$tail';
  }

  String _unsourcedResearchNote() =>
      '\n\n---\n_No sources were fetched for this answer — it comes from the '
      'model’s own knowledge, and any links above were not read. Ask it to '
      'look this up if you need something you can check._';

  /// The tail of what the user can actually see in the pane.
  ///
  /// Bounded: the server puts this in the prompt, and a session that has been
  /// open all day would otherwise send a megabyte of build output and crowd
  /// out the conversation.
  String? _recentScrollback() {
    final workspace = ref.read(shellWorkspaceProvider(arg));
    if (workspace == null) {
      debugPrint('[scrollback] no workspace for $arg');
      return null;
    }
    final lines = workspace.active.scrollback.lines;
    debugPrint('[scrollback] lines=${lines.length} '
        'ws=${identityHashCode(workspace)} '
        'pane=${identityHashCode(workspace.active)} '
        'sb=${identityHashCode(workspace.active.scrollback)}');
    if (lines.isEmpty) return null;
    const keep = 40;
    final tail =
        lines.length > keep ? lines.sublist(lines.length - keep) : lines;
    final text = [for (final l in tail) l.text].join('\n');
    // Size, not content — the terminal holds whatever the user typed. Enough
    // to tell "we sent nothing" from "we sent it and it was ignored", which is
    // the whole question when the model claims it cannot see the terminal.
    debugPrint('[scrollback] sending chars=${text.length}');
    return text;
  }

  /// Pulls readable text out of whichever frame shape carried it.
  ///
  /// Three shapes in the deployed stream: an `assistant` frame whose
  /// `message.content` is an array of typed blocks, a `result` frame with the
  /// final string, and the flat `text` the spec described. Handling all three
  /// keeps this working if the server converges on the documented one.
  static String? _textFromFrame(Map<String, dynamic> json) {
    if (json['type'] == 'result') return json['result'] as String?;

    final message = json['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String) return content;
      if (content is List) {
        final buf = StringBuffer();
        for (final block in content) {
          if (block is Map &&
              block['type'] == 'text' &&
              block['text'] is String) {
            buf.write(block['text']);
          }
        }
        final joined = buf.toString();
        if (joined.isNotEmpty) return joined;
      }
    }

    final flat = json['text'] ?? json['delta'];
    return flat is String ? flat : null;
  }

  Timer? _agentFlush;

  /// Renders assistant text, batched.
  ///
  /// Frames arrive one token at a time, and each one used to rebuild the whole
  /// message list and re-parse the markdown — O(length) work per token, which
  /// is the "streaming does not feel like streaming" the owner reported. The
  /// `/complete` path has batched since launch for exactly this reason; the
  /// run-protocol path never did.
  ///
  /// Same backing-off cadence as that path: 20fps while the reply is short,
  /// easing to 8fps as it grows, so the per-second cost stays roughly flat
  /// however long the answer runs.
  void _showAssistant(String assistantId, String text, {bool schedule = false}) {
    if (!schedule) {
      _agentFlush?.cancel();
      _agentFlush = null;
      _replaceAssistant(assistantId, _renderable(text));
      return;
    }
    _agentFlush ??= Timer(
      Duration(
        milliseconds: text.length < 2000
            ? 50
            : text.length < 6000
                ? 80
                : 120,
      ),
      () {
        _agentFlush = null;
        if (_disposed) return;
        _replaceAssistant(assistantId, _renderable(text));
      },
    );
  }

  /// Assistant text with any unexecuted call template taken out.
  ///
  /// A refused tool call comes back as the raw template inside a frame flagged
  /// success, so nothing upstream marks it as a failure and it would render as
  /// the answer. When the template was the WHOLE reply there is nothing
  /// underneath it, and an empty bubble reads as the app breaking rather than
  /// the call — so say plainly what the model reached for. Naming the tool
  /// makes it something the user can report.
  static String _renderable(String raw) {
    final thought = stripSystemDirectives(stripThinkTags(raw));
    return _render(stripToolCallTemplates(thought), thought);
  }

  static String _render(StrippedText safe, String raw) {
    if (!safe.didStrip) return raw;
    if (!safe.isOnlyToolCall) return safe.text;
    // Deliberately does NOT say the tool is missing. Both leaks seen on prod
    // named tools that ARE registered (`file_write`, `TodoWrite`) — the model
    // wrote the call out as text instead of making it, and the serving layer
    // did not parse it back. From here the two cases are indistinguishable, so
    // this describes what is certain: it was written, not run.
    return 'The model wrote out a tool call (`${safe.toolNames.first}`) as '
        'text instead of running it, so nothing happened. Asking again '
        'usually works.';
  }

  /// Sets the streaming assistant bubble's text, creating it if needed.
  ///
  /// Insert-or-replace, not replace: on the first frame there is no bubble
  /// yet. Only replacing meant every frame updated nothing and the reply never
  /// appeared — the run completed correctly and the screen stayed empty.
  void _replaceAssistant(String assistantId, String text) {
    final current = state.valueOrNull;
    if (current == null) return;
    final exists = current.messages.any((m) => m.id == assistantId);
    final messages = exists
        ? [
            for (final m in current.messages)
              if (m.id == assistantId) m.copyWith(content: text) else m,
          ]
        : [
            ...current.messages,
            MessageModel(
              id: assistantId,
              chatId: arg,
              role: 'assistant',
              content: text,
              createdAt: DateTime.now(),
            ),
          ];
    state = AsyncData((chat: current.chat, messages: messages));
  }

  /// The conversation in OpenAI shape, for a stateless local endpoint.
  ///
  /// Our own server keeps the history; a local runtime keeps nothing, so
  /// sending only the newest message would make every turn the first one.
  ///
  /// Empty and non-conversational messages are dropped: a half-streamed
  /// assistant bubble from a turn the user cancelled would otherwise be fed
  /// back as though the model had said it.
  static List<Map<String, String>> _openAiHistory(
    List<MessageModel> history,
    String newMessage,
  ) {
    return [
      for (final m in history)
        if (m.content.trim().isNotEmpty &&
            (m.role == 'user' || m.role == 'assistant'))
          {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': newMessage},
    ];
  }

  /// Single place that flips the streaming flag, so the background guard can
  /// never drift out of step with the UI's idea of whether a turn is running.
  ///
  /// Does NOT hold the CPU: this is network wait, and the radio wakes us when
  /// the bytes land. Device work asks for the CPU separately, where it happens.
  void _setStreaming(bool running, {String? label}) {
    ref.read(streamRunningProvider.notifier).state = running;
    if (running) {
      _bgRun ??= BackgroundRuns.instance.beginRun(label);
    } else {
      _bgRun?.end();
      _bgRun = null;
    }
  }

  @override
  Future<({ChatModel chat, List<MessageModel> messages})> build(
      String chatId) async {
    ref.onDispose(() {
      _disposed = true;
      // Navigating away mid-stream must release the guard too — otherwise the
      // token leaks and the notification outlives the work by 30 minutes.
      _bgRun?.end();
      _bgRun = null;
      // Reset the cross-chat GLOBAL stream flags here — ref is still valid
      // during onDispose, whereas _finishStream's disposed-guard skips them.
      // Without this, leaving a chat mid-stream strands streamRunning=true and
      // hides the Continue pill in every other chat until an unrelated send.
      ref.read(streamRunningProvider.notifier).state = false;
      ref.read(activeWebSearchProvider.notifier).state = null;
      ref.read(activeToolStatusProvider.notifier).state = null;
    });
    final repo = ref.read(chatRepositoryProvider);
    try {
      final loaded = await repo.getChatWithMessages(chatId);
      return (chat: loaded.chat, messages: await _withLocal(loaded.messages));
    } on ForbiddenException catch (_) {
      // Server returned 403. Two possibilities:
      //   (a) The chat was just created by POST /chat but isn't fully
      //       persisted server-side until the first message lands —
      //       so a follow-up GET /chat/:id 403s. Verify by checking
      //       the user's own chat list for this id; if it's there,
      //       this is a freshness race, not an authorization issue.
      //   (b) The route truly carries a chat id that doesn't belong
      //       to this user (stale id from a prior OAuth session).
      //       Re-throw so the screen can bounce to /chats.
      final list = ref.read(chatListProvider).valueOrNull ?? const [];
      final fresh = list.firstWhere(
        (c) => c.id == chatId,
        orElse: () => const ChatModel(),
      );
      if (fresh.id.isNotEmpty) {
        // It's the user's chat — show an empty state. First message
        // they send will persist server-side and subsequent fetches
        // will succeed normally.
        return (chat: fresh, messages: const <MessageModel>[]);
      }
      rethrow;
    }
  }

  /// Sends [text] (plus any optional [attachments] in the API format) and
  /// streams the assistant reply token-by-token. The assistant message
  /// accumulates live in state.
  Future<void> sendMessage(
    String text, {
    List<Map<String, dynamic>>? attachments,
  }) async {
    final current = state.requireValue;
    final repo = ref.read(chatRepositoryProvider);

    // Fail FAST when there is no connection.
    //
    // Without this the request sits until the socket times out — tens of
    // seconds of a spinner that was never going to succeed, ending in a
    // generic timeout. The device already knows it has no network, so say so
    // immediately and keep the user's text so they can resend rather than
    // retype it.
    if (ref.read(isOfflineProvider)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      state = AsyncData((
        chat: current.chat,
        messages: [
          ...current.messages,
          // Keep what they typed. The composer has already cleared itself, so
          // dropping it here would lose the text entirely and they would have
          // to retype it to retry.
          MessageModel(
            id: 'offline_user_$now',
            chatId: arg,
            role: 'user',
            content: text,
            createdAt: DateTime.now(),
          ),
          MessageModel(
            id: 'offline_note_$now',
            chatId: arg,
            role: 'assistant',
            content: "You're offline, so this wasn't sent. Your message is "
                'here — reconnect and send it again.',
            createdAt: DateTime.now(),
          ),
        ],
      ));
      return;
    }

    // Force web-search path on this turn if the user toggled it on in
    // the composer. Chat-team's inbox/019 shipped a proper
    // `forceWebSearch: true` body flag so we can send the user's
    // verbatim text and let the server bypass its heuristic. Toggle
    // resets after send so it doesn't surprise the next turn.
    final forceSearch = ref.read(webSearchToggleProvider(arg));
    if (forceSearch) {
      ref.read(webSearchToggleProvider(arg).notifier).off();
    }

    // Optimistically add user message — show the verbatim text the
    // user typed (the prior build prepended "search the web for ..."
    // before sending, which was confusing). Carry the attachments
    // through too so the inline image strip renders immediately on
    // tap-send instead of popping in only after the server echoes
    // the persisted message back.
    final userMsg = MessageModel(
      id: 'tmp_${DateTime.now().millisecondsSinceEpoch}',
      chatId: arg,
      role: 'user',
      content: text,
      attachments: [
        for (final a in attachments ?? const <Map<String, dynamic>>[])
          MessageAttachment(
            url: (a['url'] ?? '') as String,
            contentType:
                (a['contentType'] ?? 'application/octet-stream') as String,
            name: a['name'] as String?,
          ),
      ],
      createdAt: DateTime.now(),
    );
    state = AsyncData((
      chat: current.chat,
      messages: [...current.messages, userMsg],
    ));

    // Streaming assistant message (accumulated). We start with a temp
    // client-side id and swap to the server-assigned one when `start` (or
    // failing that, `done`) arrives — the real id is what /complete/resume
    // needs and what the truncated-set keys off.
    var assistantId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
    var accumulated = '';

    // Web sources fetched for this answer (from the `web-searched` status).
    // Captured here and stored under the FINAL assistant id at stream end —
    // the status arrives during the search, before the server id is swapped
    // in, so keying it now would miss the id the bubble ends up rendering.
    var searchedSources = const <String>[];

    // Token batching: tokens can arrive 50-100×/s, and emitting state per
    // token rebuilds the whole message list (and re-parses the growing
    // message's markdown) at that rate — enough to starve the UI thread
    // and freeze scrolling on long replies (reported post-launch). Instead,
    // accumulate and flush to state on a ~50ms cadence (≈20fps, visually
    // indistinguishable from per-token updates).
    Timer? flushTimer;
    void flushTokens() {
      flushTimer?.cancel();
      flushTimer = null;
      if (_disposed) return;
      final assistantMsg = MessageModel(
        id: assistantId,
        chatId: arg,
        role: 'assistant',
        // Stripped for display only — `accumulated` stays raw, because on this
        // path text arrives token by token and removing a half-written
        // template from the buffer would mangle the rest of it as it lands.
        content: _renderable(accumulated),
        createdAt: DateTime.now(),
      );
      final msgs = state.requireValue.messages;
      final existing = msgs.any((m) => m.id == assistantId);
      state = AsyncData((
        chat: state.requireValue.chat,
        messages: existing
            ? msgs.map((m) => m.id == assistantId ? assistantMsg : m).toList()
            : [...msgs, assistantMsg],
      ));
    }

    // Re-rendering the streaming bubble costs roughly O(length): the text is
    // re-segmented and the markdown re-parsed each flush. A fixed 50ms cadence
    // is fine for a short reply and drops frames on a long one, so back the
    // cadence off as the message grows. 20fps → 12fps → 8fps; still reads as
    // continuous typing, but the per-second work stays roughly flat.
    Duration flushInterval() {
      final n = accumulated.length;
      if (n < 2000) return const Duration(milliseconds: 50);
      if (n < 6000) return const Duration(milliseconds: 80);
      return const Duration(milliseconds: 120);
    }

    void scheduleFlush() {
      flushTimer ??= Timer(flushInterval(), flushTokens);
    }

    // A local model is a different protocol, not a different URL: it is
    // stateless OpenAI SSE rather than our server's event stream, so the whole
    // conversation travels with the request. LocalChatStream presents it as
    // the same StreamEvent sequence, so everything below this line is shared.
    // await, not read: the stored choice hydrates asynchronously, so a
    // synchronous read sends the first message of every launch to our servers
    // regardless of what the user picked. See localRouteResolved.
    final route = await ref.read(localRouteResolved.future);

    // An agent surface goes to the run protocol, not /complete. The difference
    // is not the URL: /complete carries the device capabilities as a STRING
    // and attaches no `tools`, so a model told about them in prose emits the
    // call template as text — the Gemma `<tool_call>` and GLM "Action:"
    // failures were both that. /agent/run attaches the eight real device tool
    // schemas (chat-team inbox/003, live 2026-08-04).
    //
    // A local model wins over both: it is the user's explicit choice, and it
    // has no tools either way.
    final surface = ref.read(agentSurfaceProvider(arg));
    if (route == null && surface != null) {
      // Name the session from what was asked. The server titles plain chats
      // from the first exchange; an agent run never reaches that path, which
      // is why every Shell row read "New Chat". Fire and forget — a rename is
      // not worth delaying the answer, and it no-ops once titled.
      unawaited(ref
          .read(chatListProvider.notifier)
          .titleFromFirstMessage(arg, text));
      await _streamAgentRun(
        text: text,
        assistantId: assistantId,
        userMessages: current.messages,
      );
      return;
    }

    final stream = route != null
        ? LocalChatStream.send(
            baseUrl: route.baseUrl,
            model: route.model,
            messages: _openAiHistory(current.messages, text),
          )
        : repo.streamCompletion(
            chatId: arg,
            message: text,
            // Use effective model — enforces free-tier lock + falls back to
            // server default if the user's saved selection is now locked.
            modelId: ref.read(effectiveModelProvider),
            attachments: attachments,
            forceWebSearch: forceSearch,
            // Tells the model it is sitting on a real shell. Computed per turn, not
            // cached: cwd, installed distro and network all move between messages.
            // Null for non-shell chats, and the server gates on section anyway.
            deviceContext: ref.read(deviceContextProvider(arg)),
          );

    _cancelRequested = false;
    // Fresh bridge per turn — synthetic call ids are per-run.
    final agentNotifier = ref.read(agentSessionProvider(arg).notifier);
    _agentBridge = AgentStatusBridge(agentNotifier);
    _setStreaming(true, label: 'Answering');
    // Clear any web-search / tool badge left over from a previous turn.
    ref.read(activeWebSearchProvider.notifier).state = null;
    ref.read(activeToolStatusProvider.notifier).state = null;

    String? streamError;
    var tokensReceived = 0;
    try {
      // Timeout if the server holds the stream open with no events.
      // Most production responses arrive in <30s; 90s is generous.
      await for (final event in stream.timeout(const Duration(seconds: 90))) {
        // Bail (cancelling the socket via the implicit subscription) if the
        // notifier was disposed mid-stream or the user tapped Stop.
        if (_disposed || _cancelRequested) break;
        event.when(
          start: (msgId, model, mode) {
            // Server-assigned message id arrives. Adopt it as the bubble's
            // canonical id so /complete/resume can target the right row.
            // If the bubble already exists (rare race with first token),
            // rename it in place; otherwise just remember the new id.
            if (msgId.isNotEmpty && msgId != assistantId) {
              final msgs = state.requireValue.messages;
              final renamed = msgs
                  .map((m) => m.id == assistantId ? m.copyWith(id: msgId) : m)
                  .toList();
              assistantId = msgId;
              state = AsyncData((
                chat: state.requireValue.chat,
                messages: renamed,
              ));
            }
          },
          token: (content) {
            tokensReceived++;
            accumulated += content;
            // First token flushes immediately (snappy perceived start);
            // the rest batch on the 50ms timer.
            if (tokensReceived == 1) {
              flushTokens();
            } else {
              scheduleFlush();
            }
          },
          usage: (inputTokens, outputTokens, totalTokens) {
            ref.read(lastTurnUsageProvider.notifier).state = TurnUsage(
              inputTokens: inputTokens,
              outputTokens: outputTokens,
              totalTokens: totalTokens,
            );
          },
          done: (msgId, finishReason, truncated, mode) {
            // Push any batched tokens into state before the rename below —
            // the bubble must exist (with full content) for the id swap.
            flushTokens();
            // Stream terminated cleanly. Refresh the chat list so the new
            // lastMessage preview + title (if it was auto-generated) appear.
            ref.invalidate(chatListProvider);
            // Clear any lingering web-search / tool badge.
            ref.read(activeWebSearchProvider.notifier).state = null;
            ref.read(activeToolStatusProvider.notifier).state = null;

            // Late-arriving server messageId (some backend variants only
            // include it in `done`, not `start`). Same swap-in-place logic.
            if (msgId != null && msgId.isNotEmpty && msgId != assistantId) {
              final msgs = state.requireValue.messages;
              final renamed = msgs
                  .map((m) => m.id == assistantId ? m.copyWith(id: msgId) : m)
                  .toList();
              assistantId = msgId;
              state = AsyncData((
                chat: state.requireValue.chat,
                messages: renamed,
              ));
            }

            // Mark this bubble as resumable if the server hit max_tokens.
            // The UI's Continue pill watches truncatedMessagesProvider.
            if (truncated && assistantId.isNotEmpty) {
              ref.read(truncatedMessagesProvider.notifier).mark(assistantId);
            }
          },
          status: (status, query, reason, resultCount, source, sources) {
            // Agent transcript: the same status events also drive tool cards
            // (see AgentStatusBridge). Until core's run protocol is exposed
            // to mobile, this is where tool activity becomes visible.
            _agentBridge?.onStatus(
              status: status,
              query: query,
              reason: reason,
              resultCount: resultCount,
              source: source,
            );
            // Chat-team's auto web-search status events (inbox/012).
            // Translate to a single WebSearchStatus that the UI watches.
            final notifier = ref.read(activeWebSearchProvider.notifier);
            switch (status) {
              case 'web-searching':
                notifier.state =
                    WebSearchStatus(phase: 'searching', query: query);
              case 'web-searched':
                notifier.state = WebSearchStatus(
                    phase: 'searched', resultCount: resultCount);
                // Stash the fetched URLs — stored under the final assistant id
                // in the stream's finally so the "Sources" chip can render.
                if (sources.isNotEmpty) searchedSources = sources;
              case 'web-search-no-results':
                notifier.state = const WebSearchStatus(phase: 'no-results');
              // Agentic tool status (inbox/025): `query` is the live
              // human-readable line ("Reading main.py").
              case 'tool-running':
                ref.read(activeToolStatusProvider.notifier).state =
                    ToolStatus(query: query);
              case 'tool-done':
                ref.read(activeToolStatusProvider.notifier).state = null;
            }
          },
          error: (msg, code) {
            // Record the error but do NOT swap state to AsyncError —
            // that would blow away the whole conversation view. The UI
            // surfaces a failure bubble inline.
            // CONTEXT_EXCEEDED gets a tailored message so the user knows
            // the fix is "start a new chat" rather than "try again".
            if (code == 'CONTEXT_EXCEEDED') {
              streamError =
                  "This conversation got too long for the model's context window. Start a new chat to continue.";
            } else {
              streamError = msg;
            }
          },
        );
      }
      // Stream closed cleanly with no error event, but also no tokens.
      // This is the "model returned nothing" silent-fail case the user hit.
      if (tokensReceived == 0 &&
          streamError == null &&
          !_cancelRequested &&
          !_disposed) {
        streamError = 'Model returned no response. Try again or switch model.';
      }
    } on async.TimeoutException {
      streamError = 'Model timed out (no response in 90s). Try a faster model.';
    } on ForbiddenException catch (_) {
      // The chat we're sending into doesn't belong to the current user
      // (most commonly: previous session's chat id was opened by
      // ChatBootstrapScreen before chatListProvider was invalidated on
      // login). Sentinel marker — the chat detail screen watches for
      // this in `lastSendStaleChatErrorProvider` and bounces the user
      // to a fresh chat + replays the same message.
      streamError = '__STALE_CHAT_403__';
      ref.read(lastSendStaleChatErrorProvider.notifier).state =
          StaleSendRecovery(originalText: text, attachments: attachments);
    } catch (e) {
      streamError = humanStreamError(e);
    } finally {
      // Deliver any tokens still sitting in the 50ms batch window — on
      // cancel/error the partial reply must still land in the transcript.
      if (!_disposed && tokensReceived > 0) flushTokens();
      flushTimer?.cancel();
      // Never leave a tool card spinning after a cancel or a dropped stream.
      if (!_disposed) _agentBridge?.onStreamEnd();
      _agentBridge = null;
      // Persist the fetched sources under the FINAL assistant id so the
      // "Sources" chip renders (and survives reload).
      if (!_disposed &&
          searchedSources.isNotEmpty &&
          assistantId.isNotEmpty) {
        ref
            .read(messageSourcesProvider.notifier)
            .set(assistantId, searchedSources);
      }
      _finishStream(streamError, assistantId, text);
    }
  }

  /// Finalizes a completed / failed / cancelled send. No-ops if the notifier
  /// was disposed mid-stream (navigation), so we never touch ref/state after
  /// dispose. (Kept out of the `finally` body to avoid control-flow-in-finally.)
  void _finishStream(String? streamError, String assistantId, String text) {
    if (_disposed) return;
    _cancelRequested = false;
    _setStreaming(false);
    ref.read(activeWebSearchProvider.notifier).state = null;
    ref.read(activeToolStatusProvider.notifier).state = null;
    if (streamError != null) {
      // Stale-chat-403: don't render a failure bubble — the screen is about to
      // navigate the user to a fresh chat and replay their message.
      if (streamError == '__STALE_CHAT_403__') {
        final current = state.valueOrNull;
        if (current != null) {
          final cleaned =
              current.messages.where((m) => m.id != assistantId).toList();
          state = AsyncData((chat: current.chat, messages: cleaned));
        }
      } else {
        // Replace the partial assistant placeholder with a failed-send bubble
        // (faded message + Retry) so the failure stays visible in context.
        final current = state.valueOrNull;
        if (current != null) {
          final cleaned =
              current.messages.where((m) => m.id != assistantId).toList();
          final errorMsg = MessageModel(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            chatId: arg,
            role: 'assistant',
            content: streamError,
            isError: true,
            retryText: text,
            createdAt: DateTime.now(),
          );
          state = AsyncData((
            chat: current.chat,
            messages: [...cleaned, errorMsg],
          ));
        }
      }
    }
  }

  /// Carries on a run that ran out of turns.
  ///
  /// Not a protocol-level resume — `/complete/resume` re-feeds a truncated
  /// assistant message, which is a different situation. A run that exhausted
  /// its budget has already changed the world: files exist on the device,
  /// packages are installed. The continuation that respects that is a new turn
  /// in the same conversation telling it to keep going, so the model sees its
  /// own prior turns and the tool results in history.
  Future<void> continueRun() =>
      sendMessage('Continue from where you stopped. Do not start over — the '
          'work you already did is still there.');

  /// Resume a truncated assistant turn by appending the continuation to
  /// the SAME bubble. Server-side `/complete/resume` re-feeds the prior
  /// turn + the partial assistant message and streams only the new bytes;
  /// we concat them onto the existing bubble — single seamless answer.
  ///
  /// Spec: chat-team inbox/014 §4. Replaces the earlier client-side
  /// "send a follow-up user message" fallback, which created a redundant
  /// user turn and gave the model latitude to repeat or preamble.
  Future<void> resumeMessage(String messageId) async {
    final repo = ref.read(chatRepositoryProvider);
    final stream = repo.streamResume(chatId: arg, messageId: messageId);

    _cancelRequested = false;
    _setStreaming(true, label: 'Answering');
    ref.read(activeWebSearchProvider.notifier).state = null;
    ref.read(activeToolStatusProvider.notifier).state = null;
    // Hide the Continue pill while resuming — if the resume itself
    // truncates again, the new `done.truncated` will re-add it.
    ref.read(truncatedMessagesProvider.notifier).clear(messageId);

    String? streamError;
    try {
      await for (final event in stream.timeout(const Duration(seconds: 90))) {
        if (_disposed || _cancelRequested) break;
        event.when(
          start: (msgId, model, mode) {
            // No bubble to create — we're appending. Just confirm targeting.
          },
          token: (content) {
            final msgs = state.requireValue.messages;
            final idx = msgs.indexWhere((m) => m.id == messageId);
            if (idx < 0) return;
            final updated = msgs[idx].copyWith(
              content: msgs[idx].content + content,
            );
            state = AsyncData((
              chat: state.requireValue.chat,
              messages: [
                ...msgs.sublist(0, idx),
                updated,
                ...msgs.sublist(idx + 1),
              ],
            ));
          },
          usage: (inputTokens, outputTokens, totalTokens) {
            ref.read(lastTurnUsageProvider.notifier).state = TurnUsage(
              inputTokens: inputTokens,
              outputTokens: outputTokens,
              totalTokens: totalTokens,
            );
          },
          done: (msgId, finishReason, truncated, mode) {
            ref.invalidate(chatListProvider);
            ref.read(activeWebSearchProvider.notifier).state = null;
            ref.read(activeToolStatusProvider.notifier).state = null;
            // Resume itself may truncate again — recursion-safe per
            // chat-team's spec; just re-mark the bubble.
            if (truncated) {
              ref.read(truncatedMessagesProvider.notifier).mark(messageId);
            }
          },
          status: (status, query, reason, resultCount, source, sources) {
            // Resume streams generally don't emit web-search status, but
            // forward defensively in case the model re-searches.
            final notifier = ref.read(activeWebSearchProvider.notifier);
            switch (status) {
              case 'web-searching':
                notifier.state =
                    WebSearchStatus(phase: 'searching', query: query);
              case 'web-searched':
                notifier.state = WebSearchStatus(
                    phase: 'searched', resultCount: resultCount);
                // Resume keeps the existing (stable) message id, so store
                // directly for the chip.
                if (sources.isNotEmpty) {
                  ref
                      .read(messageSourcesProvider.notifier)
                      .set(messageId, sources);
                }
              case 'web-search-no-results':
                notifier.state = const WebSearchStatus(phase: 'no-results');
              case 'tool-running':
                ref.read(activeToolStatusProvider.notifier).state =
                    ToolStatus(query: query);
              case 'tool-done':
                ref.read(activeToolStatusProvider.notifier).state = null;
            }
          },
          error: (msg, code) {
            // Map known server codes to clear messages so the user
            // understands WHY resume failed (not just "something broke").
            streamError = switch (code) {
              'MODEL_ACCESS_DENIED' =>
                "This model isn't available on your current plan. Upgrade to continue.",
              'EMPTY_TARGET' =>
                'Nothing to continue from. Try regenerating instead.',
              'UNSUPPORTED_PROVIDER' =>
                "Continue isn't supported for this model yet.",
              _ => msg,
            };
          },
        );
      }
    } on async.TimeoutException {
      streamError = 'Continue timed out. Try again.';
    } catch (e) {
      streamError = humanStreamError(e);
    } finally {
      // Skip cleanup if the notifier was disposed mid-resume (navigation).
      if (!_disposed) {
        _cancelRequested = false;
        _setStreaming(false);
        ref.read(activeWebSearchProvider.notifier).state = null;
        ref.read(activeToolStatusProvider.notifier).state = null;
        // Resume failures don't replace the bubble — the original truncated
        // text is still useful and stays visible. We surface the error as a
        // toast via the screen (it watches lastResumeErrorProvider).
        if (streamError != null) {
          ref.read(lastResumeErrorProvider.notifier).state = streamError;
          // Re-arm the Continue pill so the user can retry resuming.
          ref.read(truncatedMessagesProvider.notifier).mark(messageId);
        }
      }
    }
  }

  /// "Regenerate this response" — used by both the failed-bubble retry
  /// button and the assistant-message regenerate action.
  ///
  /// Drops the trailing assistant turn (error placeholder OR successful
  /// reply) AND the user message that preceded it, then re-sends. End
  /// state: [..., user(text), newAssistant] instead of [..., user, oldAssistant,
  /// user, newAssistant]. Without this pruning, retry would create 4
  /// messages for what should be 2.
  ///
  /// Note: this only cleans up CLIENT-side. The server's DB still has the
  /// old turn — proper regenerate requires a chat-team endpoint that
  /// replaces the last assistant message. Queued separately.
  Future<void> retry(String text) async {
    final current = state.valueOrNull;
    if (current != null) {
      final pruned = [...current.messages];
      // Drop trailing assistant messages (success or error).
      while (pruned.isNotEmpty && pruned.last.role == 'assistant') {
        pruned.removeLast();
      }
      // Drop the trailing user message that we're about to re-send,
      // regardless of whether the text matches (the user is asking
      // "do this turn over").
      if (pruned.isNotEmpty && pruned.last.role == 'user') {
        pruned.removeLast();
      }
      state = AsyncData((chat: current.chat, messages: pruned));
    }
    await sendMessage(text);
  }
}
