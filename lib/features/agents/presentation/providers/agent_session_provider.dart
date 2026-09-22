import 'package:cyberneurova_mobile/core/agent/run_store.dart';
import 'package:cyberneurova_mobile/core/agent/neurova_home.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_outbox.dart';
import 'package:cyberneurova_mobile/core/agent/agent_session.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/core/agent/run_protocol_channel.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';

/// Where control messages go for a given chat.
///
/// Returns [UnavailableControlChannel] until core exposes a control endpoint
/// (`docs/ENGINE.md` §4.1, `docs/RUN_PROTOCOL.md` §3). That is deliberate
/// rather than a stub that pretends to work: an undeliverable approval must
/// surface as undelivered, because the run stays paused until it lands.
///
/// When the endpoint exists, this becomes:
///
/// ```dart
/// return HttpAgentControlChannel(
///   client: ref.watch(apiClientProvider),
///   path: ApiConstants.agentControl(chatId),
/// );
/// ```
///
/// Nothing else in the app changes — [AgentSession] and the UI are already
/// written against the interface.
/// The run id, held apart from both the session and the channel.
///
/// It cannot live on either. The channel needs it to address a result, and the
/// session needs the channel to send one — so a channel that reads the session
/// closes a loop, and Riverpod throws `CircularDependencyError` the moment the
/// closure runs. That failed every device result before it reached HTTP, and
/// the user saw "Couldn't reach the agent" for what was never a network
/// problem. Found on device 2026-08-04; the run had written the file
/// correctly and only the result could not be delivered.
///
/// A holder that depends on nothing breaks the loop without either side
/// having to know about the other.
final runIdHolderProvider =
    Provider.family<RunIdHolder, String>((ref, chatId) => RunIdHolder());

class RunIdHolder {
  /// Null until the first frame that carries one. A result sent before then
  /// has nothing to address, so the outbox holds it and retries.
  String? value;
}

/// Where the device's half of a run is sent.
///
/// Was a placeholder returning [UnavailableControlChannel] while the run
/// protocol was undeployed — every device result was queued and never
/// delivered, which is why a tool call could never complete. Live since
/// 2026-08-04 (chat-team inbox/003).
final agentControlChannelProvider =
    Provider.family<AgentControlChannel, String>((ref, chatId) {
  return RunProtocolChannel(
    client: ref.watch(apiClientProvider),
    runId: () => ref.read(runIdHolderProvider(chatId)).value,
  );
});

/// Per-chat agent run: transcript, outbound control queue, resume state.
///
/// Kept separate from `chatDetailProvider` because the two have different
/// lifetimes — messages are server-persisted conversation, while run state
/// exists only while a run is live or replayable.
final agentSessionProvider =
    NotifierProvider.family<AgentSessionNotifier, AgentSession, String>(
  AgentSessionNotifier.new,
);

/// Where a run's tool activity is written down.
///
/// One store for the whole app; the chat id keys the file.
final runStoreProvider = FutureProvider<RunStore>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return RunStore(Directory('${dir.path}/runs'));
});

/// `~/.neurova` inside the user's shell home — see [NeurovaHome].
///
/// Hangs off the shell root rather than the app documents directory on
/// purpose: the point of it is that the user can open it from their own
/// terminal on the phone.
final neurovaHomeProvider = FutureProvider<NeurovaHome>((ref) async {
  final home = await ref.watch(shellRootDirProvider.future);
  final neurova = NeurovaHome(home);
  await neurova.ensure();
  return neurova;
});

/// Conversations stored on the device, under `~/.neurova/chats`.
final localChatStoreProvider = FutureProvider<LocalChatStore>((ref) async {
  return LocalChatStore(await ref.watch(neurovaHomeProvider.future));
});

class AgentSessionNotifier extends FamilyNotifier<AgentSession, String> {
  Timer? _saveDebounce;

  @override
  AgentSession build(String chatId) {
    final session = AgentSession(
      channel: ref.watch(agentControlChannelProvider(chatId)),
      // Tool calls tagged `executor: "device"` run here rather than on the
      // server — scans and LAN probes never leave the phone.
      deviceExecutor: ref.watch(deviceExecutorProvider(chatId)),
      // [AgentSession] mutates in place — a transcript can hold hundreds of
      // items and rebuilding it per token would be wasteful — so identity
      // never changes and this is what drives rebuilds.
      onChanged: () {
        ref.notifyListeners();
        _scheduleSave(chatId);
      },
    );

    // Put back what the last run left, before anything else touches the
    // transcript. Without this, reopening a chat showed nothing the agent had
    // ever done — the conversation survives on the server, the tool activity
    // only ever existed here.
    unawaited(_restore(chatId, session));

    ref.onDispose(() {
      _saveDebounce?.cancel();
      session.dispose();
    });
    return session;
  }

  Future<void> _restore(String chatId, AgentSession session) async {
    final store = await ref.read(runStoreProvider.future);
    final saved = await store.load(chatId);
    if (saved == null || saved.isEmpty) return;
    session.runId ??= saved.runId;
    session.transcript.restore(saved.cards);
    ref.notifyListeners();
  }

  /// Debounced: a running tool emits progress lines continuously, and writing
  /// the file per line would be the most expensive thing in the run.
  void _scheduleSave(String chatId) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), () async {
      final store = await ref.read(runStoreProvider.future);
      await store.save(
        chatId,
        runId: state.runId,
        transcript: state.transcript,
      );
    });
  }

  void apply(AgentFrame frame, {String? runId}) {
    // The one funnel every frame passes through, so the holder the channel
    // reads is filled here rather than at each call site.
    if (runId != null && runId.isNotEmpty) {
      ref.read(runIdHolderProvider(arg)).value = runId;
    }
    state.applyFrame(frame, frameRunId: runId);
  }

  void addUserMessage(String text) {
    state.transcript.addUserMessage(text);
    ref.notifyListeners();
  }

  OutboxEntry respondToApproval(
    String callId, {
    required ApprovalDecision decision,
    Map<String, dynamic>? editedInput,
  }) =>
      state.respondToApproval(
        callId,
        decision: decision,
        editedInput: editedInput,
      );

  OutboxEntry cancel({String? callId}) => state.cancel(callId: callId);

  OutboxEntry? resume() => state.resume();

  void retryFailedControl() => state.retryFailedControl();

  void clear() => state.clear();
}

/// Converts the chat stream's `status` events into agent frames.
///
/// The backend's existing status vocabulary (chat-team inbox/012 and /025)
/// already carries real tool activity — a web search with a query and a
/// result count, an agentic step with a line like "Reading main.py". Until
/// now those only drove a label on the typing indicator, discarding most of
/// the information.
///
/// Stateful by necessity: status events carry no call id, so it synthesises
/// one per started tool and closes the most recent open card on the matching
/// completion event. That models exactly what the backend tells us — no more.
///
/// **Delete this once core emits real frames.** Both paths already converge
/// on the same reducer, so the UI is unaffected.
class AgentStatusBridge {
  AgentStatusBridge(this._notifier);

  final AgentSessionNotifier _notifier;

  int _counter = 0;
  String? _openWebSearchId;
  String? _openToolId;

  String _nextId(String prefix) => '$prefix-${_counter++}';

  void onStatus({
    required String status,
    String? query,
    String? reason,
    int? resultCount,
    String? source,
  }) {
    switch (status) {
      case 'web-searching':
        final id = _nextId('websearch');
        _openWebSearchId = id;
        _notifier.apply(AgentToolCall(
          callId: id,
          tool: 'WebSearch',
          input: {if (query != null && query.isNotEmpty) 'query': query},
        ));

      case 'web-searched':
        final id = _openWebSearchId;
        if (id == null) return;
        _openWebSearchId = null;
        _notifier.apply(AgentToolResult(
          callId: id,
          ok: true,
          summary: resultCount != null
              ? 'Found $resultCount result${resultCount == 1 ? '' : 's'}'
              : 'Search complete',
        ));

      case 'web-search-no-results':
        final id = _openWebSearchId;
        if (id == null) return;
        _openWebSearchId = null;
        _notifier.apply(
            AgentToolResult(callId: id, ok: true, summary: 'No results'));

      case 'tool-running':
        final id = _nextId('tool');
        _openToolId = id;
        _notifier.apply(AgentToolCall(
          callId: id,
          tool: 'Tool',
          input: const {},
          title: (query != null && query.isNotEmpty) ? query : null,
        ));

      case 'tool-done':
        final id = _openToolId;
        if (id == null) return;
        _openToolId = null;
        _notifier.apply(AgentToolResult(callId: id, ok: true));
    }
  }

  /// Closes anything still open when the stream ends, so a card can't be left
  /// spinning after a cancel or a dropped connection.
  void onStreamEnd() {
    for (final id in [_openWebSearchId, _openToolId]) {
      if (id != null) _notifier.apply(AgentToolResult(callId: id, ok: true));
    }
    _openWebSearchId = null;
    _openToolId = null;
  }
}
