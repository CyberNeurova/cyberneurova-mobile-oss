import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_stream_frame.dart';
import 'package:cyberneurova_mobile/features/bots/data/repositories/bot_repository.dart';

/// A clean message for the DM error banner.
///
/// A provider has no BuildContext, so it can't call `userMessageFor`; storing
/// `e.toString()` instead leaked a raw exception ("Instance of
/// 'ServerException'") into the banner. Every backend failure is an
/// [AppException] whose `message` is already user-facing (a 5xx becomes
/// "Server error. We're on it."), so surface that and fall back to a generic
/// line for anything unexpected.
String botErrorText(Object e) =>
    e is AppException ? e.message : 'Something went wrong. Please try again.';

// ── Contacts (agents) ────────────────────────────────────────────────────────
final botContactsProvider =
    AsyncNotifierProvider<BotContactsNotifier, List<BotAgent>>(
  BotContactsNotifier.new,
);

class BotContactsNotifier extends AsyncNotifier<List<BotAgent>> {
  BotRepository get _repo => ref.read(botRepositoryProvider);

  @override
  Future<List<BotAgent>> build() => _repo.listAgents();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.listAgents);
  }

  /// Creates a contact and appends it to the list. Throws on failure — the
  /// caller surfaces the message.
  Future<BotAgent?> createContact({
    required String name,
    String? title,
    String? model,
    String? instructions,
  }) async {
    final agent = await _repo.createAgent(
      name: name,
      title: title,
      model: model,
      instructions: instructions,
    );
    if (agent != null) {
      state = AsyncData([...?state.valueOrNull, agent]);
    }
    return agent;
  }

  /// Opens (or returns) the DM room for [agentId]. Throws `403`
  /// (feature_requires_upgrade) on a free tier — DMs need a paid plan (§8).
  Future<BotRoom?> openDm(String agentId) => _repo.createDmRoom(agentId);
}

// ── Group rooms (the Groups section of Bot Chat) ─────────────────────────────
final botGroupsProvider =
    AsyncNotifierProvider<BotGroupsNotifier, List<BotRoom>>(
  BotGroupsNotifier.new,
);

class BotGroupsNotifier extends AsyncNotifier<List<BotRoom>> {
  BotRepository get _repo => ref.read(botRepositoryProvider);

  @override
  Future<List<BotRoom>> build() => _repo.listGroups();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.listGroups);
  }

  /// Creates a group room and prepends it (newest-first, like an inbox).
  /// Throws `403 feature_requires_upgrade` on a non-pro tier (§8) — the caller
  /// surfaces the upsell.
  Future<BotRoom?> createGroup({String? title}) async {
    final room = await _repo.createGroupRoom(title: title);
    if (room != null) {
      state = AsyncData([room, ...?state.valueOrNull]);
    }
    return room;
  }
}

// ── Device presence (executor availability) ──────────────────────────────────
/// The user's devices with an `online` flag (§4). Drives the executor-presence
/// indicator; auto-disposes so it's a fresh read each time the section opens.
final botPresenceProvider = FutureProvider.autoDispose<List<BotPresence>>((ref) {
  return ref.read(botRepositoryProvider).getPresence();
});

// ── One agent (for the profile view) ─────────────────────────────────────────
/// Resolves an agent by id — prefers the already-loaded contacts list, falls
/// back to a direct fetch so a deep-linked DM still gets a profile.
final botAgentProvider =
    FutureProvider.autoDispose.family<BotAgent?, String>((ref, agentId) async {
  final loaded = ref.watch(botContactsProvider).valueOrNull ?? const [];
  for (final a in loaded) {
    if (a.agentId == agentId) return a;
  }
  return ref.read(botRepositoryProvider).getAgent(agentId);
});

// ── One room's messages + live tail ──────────────────────────────────────────
final botChatProvider =
    NotifierProvider.autoDispose.family<BotChatNotifier, BotChatState, String>(
  BotChatNotifier.new,
);

class BotChatState {
  const BotChatState({
    this.messages = const [],
    this.loading = true,
    this.error,
    this.sending = false,
  });

  final List<BotMessage> messages;
  final bool loading;
  final String? error;
  final bool sending;

  BotChatState copyWith({
    List<BotMessage>? messages,
    bool? loading,
    bool? sending,
    String? error,
    bool clearError = false,
  }) {
    return BotChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns one room's message list, its live SSE tail, and sending. The stream is
/// the multiplexed `/bot/stream` filtered to this room (§4); the durable truth
/// is the `(roomId, seq)` log, so everything de-dups on [BotMessage.seq] and a
/// reconnect catches up from the last seq rather than replaying blindly.
class BotChatNotifier extends AutoDisposeFamilyNotifier<BotChatState, String> {
  StreamSubscription<BotStreamEvent>? _sub;
  bool _closed = false;
  int _lastSeq = 0;

  BotRepository get _repo => ref.read(botRepositoryProvider);
  late String _roomId;

  @override
  BotChatState build(String roomId) {
    _roomId = roomId;
    ref.onDispose(() {
      _closed = true;
      _sub?.cancel();
    });
    _load();
    _listen();
    return const BotChatState();
  }

  Future<void> _load() async {
    try {
      final msgs = await _repo.getMessages(_roomId);
      if (_closed) return;
      _trackSeq(msgs);
      state = state.copyWith(messages: msgs, loading: false, clearError: true);
    } catch (e) {
      if (_closed) return;
      state = state.copyWith(loading: false, error: botErrorText(e));
    }
  }

  /// Holds the SSE with reconnect. `await for` blocks until the stream ends;
  /// on end we back off, pull anything missed during the gap, then re-open.
  Future<void> _listen() async {
    while (!_closed) {
      try {
        final stream = _repo.streamEvents();
        await for (final event in stream) {
          if (_closed) return;
          if (event is BotMessageEvent && event.roomId == _roomId) {
            _apply(event.message);
          }
        }
      } catch (_) {
        // fall through to reconnect
      }
      if (_closed) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_closed) return;
      await _catchUp();
    }
  }

  Future<void> _catchUp() async {
    try {
      final msgs = await _repo.getMessages(_roomId, afterSeq: _lastSeq);
      if (_closed) return;
      for (final m in msgs) {
        _apply(m);
      }
    } catch (_) {}
  }

  void _apply(BotMessage m) {
    if (m.seq <= _lastSeq) return; // replay / duplicate
    _lastSeq = m.seq;
    final next = [...state.messages, m]..sort((a, b) => a.seq.compareTo(b.seq));
    state = state.copyWith(messages: next);
  }

  void _trackSeq(List<BotMessage> msgs) {
    for (final m in msgs) {
      if (m.seq > _lastSeq) _lastSeq = m.seq;
    }
  }

  Future<void> send(
    String text, {
    List<Map<String, dynamic>> attachmentBlocks = const [],
  }) async {
    final t = text.trim();
    if ((t.isEmpty && attachmentBlocks.isEmpty) || state.sending) return;
    state = state.copyWith(sending: true, clearError: true);
    try {
      final BotMessage? msg;
      if (attachmentBlocks.isEmpty) {
        msg = await _repo.sendMessage(_roomId, text: t, clientNonce: _nonce());
      } else {
        msg = await _repo.sendMessage(
          _roomId,
          blocks: [
            if (t.isNotEmpty) {'type': 'text', 'text': t},
            ...attachmentBlocks,
          ],
          clientNonce: _nonce(),
        );
      }
      if (_closed) return;
      if (msg != null) _apply(msg);
      state = state.copyWith(sending: false);
    } catch (e) {
      if (_closed) return;
      state = state.copyWith(sending: false, error: botErrorText(e));
    }
  }

  Future<void> retryLoad() => _load();

  // Idempotency key so a mobile-network retry can't double-post (§ messages).
  String _nonce() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';
}
