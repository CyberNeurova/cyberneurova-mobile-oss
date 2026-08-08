/// Messages the client sends *up* to a run.
///
/// The inbound half ([AgentFrame]) is what the run tells the app. This is the
/// other direction: the user's answer to an approval prompt, a request to
/// stop a tool, and the resume handshake after a dropped connection.
///
/// Deliberately transport-agnostic. Core may expose control over a WebSocket
/// (like `SessionsWebSocket`) or as plain POSTs alongside an SSE stream; the
/// message shapes are the same either way, so only [AgentControlChannel]
/// changes.
library;

/// What the user chose on an approval card.
enum ApprovalDecision {
  approve,

  /// Promotes this specific `(tool, target)` pair to allow for the rest of
  /// the session. Not the tool globally, and not across sessions.
  approveForSession,

  deny,
}

extension ApprovalDecisionWire on ApprovalDecision {
  String get wireValue => switch (this) {
        ApprovalDecision.approve => 'approve',
        ApprovalDecision.approveForSession => 'approve_for_session',
        ApprovalDecision.deny => 'deny',
      };
}

sealed class AgentControlMessage {
  const AgentControlMessage();

  Map<String, dynamic> toJson();

  /// Identity used to collapse duplicates in the outbox. Two messages with
  /// the same key are the same intent — re-tapping Approve must not enqueue
  /// a second response.
  String get dedupeKey;

  /// Whether re-sending after a failure is safe. Every control message is
  /// idempotent server-side (they all name a specific `call_id` or `seq`),
  /// which is what makes retry-on-reconnect correct rather than risky.
  bool get isIdempotent => true;
}

/// The user's answer to an `approval_request`.
final class ApprovalResponseMessage extends AgentControlMessage {
  const ApprovalResponseMessage({
    required this.callId,
    required this.decision,
    this.editedInput,
  });

  final String callId;
  final ApprovalDecision decision;

  /// Present only when the user edited the arguments before approving.
  /// Sending it replaces the call's input server-side.
  final Map<String, dynamic>? editedInput;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'approval_response',
        'call_id': callId,
        'decision': decision.wireValue,
        if (editedInput != null) 'input': editedInput,
      };

  @override
  String get dedupeKey => 'approval:$callId';
}

/// Stops a running tool, or the whole run when [callId] is null.
final class CancelMessage extends AgentControlMessage {
  const CancelMessage({this.callId});

  final String? callId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'cancel',
        if (callId != null) 'call_id': callId,
      };

  @override
  String get dedupeKey => 'cancel:${callId ?? '*'}';
}

/// Asks the server to replay from [fromSeq] after a reconnect.
final class ResumeMessage extends AgentControlMessage {
  const ResumeMessage({required this.runId, required this.fromSeq});

  final String runId;

  /// Highest sequence number the client has already folded in. The server
  /// replays everything *after* this.
  final int fromSeq;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'resume',
        'run_id': runId,
        'from_seq': fromSeq,
      };

  /// Only ever one resume in flight per run — a later one supersedes it.
  @override
  String get dedupeKey => 'resume:$runId';
}

/// Result of a tool the **device** executed, posted back to the run.
///
/// This is the return leg of the device-executor path: the server dispatched
/// a `tool_call` with `executor: "device"`, the phone ran it, and this
/// carries the outcome back. Named `device_tool_result` (not `tool_result`)
/// per `docs/shell/05-REMOTE-EXECUTOR.md` §4.2, so the server can tell a
/// device-side result from one of its own.
final class DeviceToolResultMessage extends AgentControlMessage {
  const DeviceToolResultMessage({
    required this.callId,
    required this.ok,
    this.summary,
    this.output,
    this.error,
    this.artifacts = const [],
  });

  final String callId;
  final bool ok;
  final String? summary;
  final String? output;
  final String? error;
  final List<Map<String, dynamic>> artifacts;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'device_tool_result',
        'call_id': callId,
        'ok': ok,
        if (summary != null) 'summary': summary,
        if (output != null) 'output': output,
        if (error != null) 'error': error,
        if (artifacts.isNotEmpty) 'artifacts': artifacts,
      };

  @override
  String get dedupeKey => 'device_result:$callId';
}

/// Transport for control messages.
///
/// Implementations must throw on failure so [AgentOutbox] can retry;
/// swallowing errors here would silently strand a paused run.
abstract class AgentControlChannel {
  /// True when the channel can actually reach a run. False means the backend
  /// isn't wired yet — callers should keep the UI honest rather than
  /// pretending a decision was delivered.
  bool get isConnected;

  Future<void> send(AgentControlMessage message);
}

/// Stand-in used until core exposes a control endpoint.
///
/// Reports `isConnected == false` and throws on send, so the outbox surfaces
/// an undelivered state instead of the UI quietly claiming success. That
/// distinction matters: an approval that never arrives leaves the run paused
/// forever, and the user needs to see that rather than assume it worked.
class UnavailableControlChannel implements AgentControlChannel {
  const UnavailableControlChannel();

  @override
  bool get isConnected => false;

  @override
  Future<void> send(AgentControlMessage message) =>
      throw const AgentControlUnavailable();
}

class AgentControlUnavailable implements Exception {
  const AgentControlUnavailable();
  @override
  String toString() =>
      'The agent control channel is not connected for this session.';
}
