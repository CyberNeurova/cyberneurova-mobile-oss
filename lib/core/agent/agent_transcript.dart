import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';

/// Lifecycle of one tool call.
///
/// ```
/// pending → approvalRequired → running → succeeded
///                            ↘ denied     ↘ failed
///                                         ↘ cancelled
/// ```
enum ToolCardState {
  pending,
  approvalRequired,
  running,
  succeeded,
  failed,
  denied,
  cancelled,
}

extension ToolCardStateX on ToolCardState {
  bool get isTerminal =>
      this == ToolCardState.succeeded ||
      this == ToolCardState.failed ||
      this == ToolCardState.denied ||
      this == ToolCardState.cancelled;

  bool get isActive =>
      this == ToolCardState.pending || this == ToolCardState.running;
}

/// One entry in the agent transcript.
sealed class TranscriptItem {
  const TranscriptItem();

  /// Stable identity for list keys. Must not change as the item mutates.
  String get key;
}

final class AssistantMessageItem extends TranscriptItem {
  AssistantMessageItem({required this.id, String text = ''}) : _text = text;

  final String id;
  String _text;
  String get text => _text;

  void append(String delta) => _text += delta;

  @override
  String get key => 'assistant:$id';
}

final class UserMessageItem extends TranscriptItem {
  const UserMessageItem({required this.id, required this.text});
  final String id;
  final String text;
  @override
  String get key => 'user:$id';
}

/// A tool call and everything that happens to it.
final class ToolCardItem extends TranscriptItem {
  ToolCardItem({
    required this.callId,
    required this.tool,
    required Map<String, dynamic> input,
    this.title,
    this.state = ToolCardState.pending,
  }) : _input = input;

  final String callId;
  final String tool;
  final String? title;

  Map<String, dynamic> _input;
  Map<String, dynamic> get input => _input;

  ToolCardState state;

  /// Why approval was requested, when [state] is `approvalRequired`.
  String? rationale;
  String? risk;

  /// Bounded live tail of tool output. Capped so a chatty tool can't grow
  /// the transcript without limit — the full output arrives in [output].
  final List<String> progressLines = [];
  static const _maxProgressLines = 200;

  String? summary;
  String? output;
  String? error;
  List<AgentArtifact> artifacts = const [];

  DateTime? startedAt;
  DateTime? endedAt;

  Duration? get elapsed {
    if (startedAt == null) return null;
    return (endedAt ?? DateTime.now()).difference(startedAt!);
  }

  void appendProgress(String text) {
    if (text.isEmpty) return;
    for (final line in text.split('\n')) {
      progressLines.add(line);
    }
    if (progressLines.length > _maxProgressLines) {
      progressLines.removeRange(0, progressLines.length - _maxProgressLines);
    }
  }

  /// Applied when the user edits arguments before approving.
  void replaceInput(Map<String, dynamic> next) => _input = next;

  @override
  String get key => 'tool:$callId';
}

final class ErrorItem extends TranscriptItem {
  const ErrorItem({required this.id, required this.message, this.code});
  final String id;
  final String message;
  final String? code;
  @override
  String get key => 'error:$id';
}

/// Ordered transcript plus the run's liveness, built by folding frames.
///
/// Pure Dart on purpose: no Flutter import, no platform code. This is the
/// most logic-dense part of the agent client and it must be testable under
/// `dart test` without a device.
class AgentTranscript {
  final List<TranscriptItem> items = [];

  /// Highest sequence number processed. Sent on reconnect so the server
  /// replays only what was missed.
  int? lastSeq;

  bool isRunning = false;

  /// Tool cards by call id, for O(1) update on progress/result frames.
  final Map<String, ToolCardItem> _cards = {};

  AssistantMessageItem? _openAssistant;
  int _counter = 0;

  bool get hasPendingApproval =>
      _cards.values.any((c) => c.state == ToolCardState.approvalRequired);

  List<ToolCardItem> get activeCards =>
      [for (final c in _cards.values) if (c.state.isActive) c];

  /// Folds one frame into the transcript. Returns true when the transcript
  /// changed and the UI should rebuild.
  bool apply(AgentFrame frame) {
    if (frame.seq != null) {
      // Replay after a reconnect can redeliver frames we already folded in.
      if (lastSeq != null && frame.seq! <= lastSeq!) return false;
      lastSeq = frame.seq;
    }

    switch (frame) {
      case AgentAssistantDelta(:final text):
        isRunning = true;
        final open = _openAssistant;
        if (open == null) {
          final msg = AssistantMessageItem(id: _nextId(), text: text);
          _openAssistant = msg;
          items.add(msg);
        } else {
          open.append(text);
        }
        return true;

      case AgentToolCall(:final callId, :final tool, :final input, :final title):
        isRunning = true;
        // A tool call closes the current prose block — the next delta starts
        // a new message below the card, which is how the model's narration
        // stays interleaved with its actions in the right order.
        _openAssistant = null;
        final existing = _cards[callId];
        if (existing != null) {
          existing.replaceInput(input);
          return true;
        }
        final card = ToolCardItem(
          callId: callId,
          tool: tool,
          input: input,
          title: title,
          state: ToolCardState.running,
        )..startedAt = DateTime.now();
        _cards[callId] = card;
        items.add(card);
        return true;

      case AgentApprovalRequest(
          :final callId,
          :final tool,
          :final input,
          :final rationale,
          :final risk
        ):
        isRunning = true;
        _openAssistant = null;
        final card = _cards[callId] ??
            ToolCardItem(callId: callId, tool: tool, input: input);
        if (!_cards.containsKey(callId)) {
          _cards[callId] = card;
          items.add(card);
        }
        card
          ..replaceInput(input)
          ..state = ToolCardState.approvalRequired
          ..rationale = rationale
          ..risk = risk;
        return true;

      case AgentToolProgress(:final callId, :final text):
        final card = _cards[callId];
        if (card == null) return false;
        if (card.state == ToolCardState.pending) {
          card.state = ToolCardState.running;
        }
        card.appendProgress(text);
        return true;

      case AgentToolResult(
          :final callId,
          :final ok,
          :final summary,
          :final output,
          :final error,
          :final artifacts
        ):
        final card = _cards[callId];
        if (card == null) return false;
        // A later result must not blank out detail an earlier one carried.
        //
        // Two results arrive for the same call: ours, posted the moment the
        // device finished, carrying the real reason — and the server's echo of
        // it a moment later, which drops `error` entirely (frames captured
        // 2026-08-05, outbox 052). Assigning unconditionally meant the echo
        // erased the reason and a refused call expanded to nothing but its
        // arguments. Whoever knows something wins over whoever knows nothing.
        card
          ..state = ok ? ToolCardState.succeeded : ToolCardState.failed
          ..summary = summary ?? card.summary
          ..output = output ?? card.output
          ..error = error ?? card.error
          ..artifacts = artifacts.isNotEmpty ? artifacts : card.artifacts
          ..endedAt = DateTime.now();
        // Narration after a result belongs to a new message.
        _openAssistant = null;
        return true;

      case AgentRunFinished():
        isRunning = false;
        _openAssistant = null;
        // Anything still active when the run ends was cut short.
        for (final card in _cards.values) {
          if (card.state.isActive) {
            card
              ..state = ToolCardState.cancelled
              ..endedAt = DateTime.now();
          }
        }
        return true;

      case AgentError(:final message, :final code):
        isRunning = false;
        _openAssistant = null;
        items.add(ErrorItem(id: _nextId(), message: message, code: code));
        return true;
    }
  }

  /// Records a locally-known user turn so the transcript reads as a
  /// conversation rather than a log of the assistant talking to itself.
  void addUserMessage(String text) {
    _openAssistant = null;
    items.add(UserMessageItem(id: _nextId(), text: text));
  }

  /// Marks a card denied after the user rejects an approval. The server is
  /// authoritative, but reflecting it immediately keeps the UI honest while
  /// the response is in flight.
  void markDenied(String callId) {
    final card = _cards[callId];
    if (card == null) return;
    card
      ..state = ToolCardState.denied
      ..endedAt = DateTime.now();
  }

  /// Moves an approved card into `running` optimistically.
  void markApproved(String callId, {Map<String, dynamic>? editedInput}) {
    final card = _cards[callId];
    if (card == null) return;
    if (editedInput != null) card.replaceInput(editedInput);
    card
      ..state = ToolCardState.running
      ..startedAt ??= DateTime.now();
  }

  /// Puts cards back after a restart, before any frames arrive.
  ///
  /// They are registered in the card index as well as the item list, so a run
  /// that resumes and reports on `call_id` updates the restored card instead
  /// of appending a duplicate beside it.
  void restore(List<ToolCardItem> cards) {
    for (final c in cards) {
      if (_cards.containsKey(c.callId)) continue;
      _cards[c.callId] = c;
      items.add(c);
    }
  }

  void clear() {
    items.clear();
    _cards.clear();
    _openAssistant = null;
    lastSeq = null;
    isRunning = false;
  }

  String _nextId() => '${_counter++}';
}
