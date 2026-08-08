import 'dart:async';

import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_outbox.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/retry_policy.dart';

/// Owns one chat's agent run: the transcript, the outbound control queue,
/// and the resume handshake.
///
/// Pure Dart — no Flutter, no Riverpod. The provider layer wraps this; the
/// logic lives here so it can be tested without a device.
class AgentSession {
  AgentSession({
    required AgentControlChannel channel,
    this.deviceExecutor,
    Future<void> Function(Duration)? delay,
    this.onChanged,
  }) : _channel = channel {
    _outbox = AgentOutbox(
      channel: channel,
      delay: delay,
      onChanged: () => onChanged?.call(),
    );
  }

  final AgentTranscript transcript = AgentTranscript();
  late final AgentOutbox _outbox;
  AgentControlChannel _channel;

  final void Function()? onChanged;

  /// Runs tool calls the server tagged `executor: "device"`.
  ///
  /// This is the load-shedding path: the VPS orchestrates (cheap — mostly
  /// waiting on the model) while scans, probes and LAN work happen on the
  /// phone. It is also the only way to reach the user's own network, which
  /// a server-side container never can.
  final DeviceExecutor? deviceExecutor;

  /// Server-assigned run identity, learned from the first frame that carries
  /// it. Required to resume — without it a reconnect can only start over.
  String? runId;

  AgentOutbox get outbox => _outbox;
  bool get isConnected => _channel.isConnected;

  /// True when a decision the user made hasn't reached the server. The UI
  /// shows this rather than claiming the run moved on, because a lost
  /// approval leaves the run paused indefinitely.
  bool get hasUndeliveredControl => _outbox.hasUndelivered;
  bool get hasFailedControl => _outbox.hasFailures;

  // ── Inbound ────────────────────────────────────────────────────────────

  /// Folds a frame in. Returns true when the UI should rebuild.
  bool applyFrame(AgentFrame frame, {String? frameRunId}) {
    if (frameRunId != null && frameRunId.isNotEmpty) runId = frameRunId;
    final changed = transcript.apply(frame);
    if (changed) onChanged?.call();

    // A device-executor call is a request to *do* something here, not just
    // render it. Fire and forget — the result goes back through the outbox.
    if (frame is AgentToolCall && frame.runsOnDevice) {
      unawaited(_runOnDevice(frame));
    }
    return changed;
  }

  /// Executes a device tool call and posts the result back.
  ///
  /// Progress is folded into the local transcript as it streams so the card
  /// shows motion, and is *not* sent upstream — the server does not need a
  /// packet-by-packet replay of a scan, only the outcome.
  Future<void> _runOnDevice(AgentToolCall call) async {
    // A replayed `tool_call` must not run the tool a second time.
    //
    // 029 check 3 asks the SERVER not to apply a `device_result` twice. This
    // is our half of the same rule, and it is the half with teeth: the server
    // double-applying gives the model a doubled world, but us double-executing
    // actually does the thing twice on the user's phone — a second `rm`, a
    // second `apt install`, a second POST.
    //
    // The seq guard in the chat stream does not cover this. `lastSeq` is a
    // local in one send, so a reconnect inside that send is deduped and a
    // resume that replays earlier frames — a new send, counter back to -1 —
    // is not. This is the only place that sees every call, so the guard
    // belongs here.
    //
    // A replay usually means our result never arrived, so the answer is not
    // to go quiet: re-post the result we already have.
    final previous = _completedCalls[call.callId];
    if (previous != null) {
      _outbox.enqueue(previous);
      return;
    }
    if (!_runningCalls.add(call.callId)) return;

    try {
      await _executeOnDevice(call);
    } finally {
      _runningCalls.remove(call.callId);
    }
  }

  /// Calls that have finished, with the result we sent, keyed by call id.
  ///
  /// Held for the life of the session rather than the run: a resume can replay
  /// a call from an earlier run, and re-executing then is the same mistake.
  final Map<String, DeviceToolResultMessage> _completedCalls = {};

  /// Calls executing right now. A replay while one is in flight is dropped —
  /// the result will be posted when it finishes.
  final Set<String> _runningCalls = {};

  Future<void> _executeOnDevice(AgentToolCall call) async {
    final executor = deviceExecutor;
    if (executor == null) {
      _post(DeviceToolResultMessage(
        callId: call.callId,
        ok: false,
        error: 'Device tools are not available in this session. They run '
            'only in Shell sessions, where the user has declared an '
            'authorized scope.',
      ));
      return;
    }

    // Retried here rather than surfaced as a button. A phone loses Wi-Fi for
    // a second, a host is asleep, the distro is still extracting — none of
    // those are things a person should have to notice and tap through, and
    // none of them are worth spending a model turn on. See retry_policy.dart
    // for why only some tools qualify.
    var attempt = 1;
    late DeviceToolResult result;
    while (true) {
      result = await executor.execute(
        callId: call.callId,
        tool: call.tool,
        args: call.input,
        onProgress: (line) {
          transcript.apply(
              AgentToolProgress(callId: call.callId, text: line));
          onChanged?.call();
        },
      );

      if (result.ok ||
          !shouldRetryDeviceCall(
            tool: call.tool,
            error: result.error ?? result.summary,
            attempt: attempt,
          )) {
        break;
      }

      transcript.apply(AgentToolProgress(
        callId: call.callId,
        text: 'Attempt $attempt failed — retrying…',
      ));
      onChanged?.call();
      await Future<void>.delayed(deviceRetryBackoff(attempt));
      attempt++;
    }

    // Said out loud when it took more than one go. The model is deciding what
    // to do next from this summary, and "it worked" and "it worked on the
    // third try" should lead to different decisions about what to trust.
    // A failure has to carry its reason in `summary`, not only in `error`.
    //
    // Frame capture on device (2026-08-05): a refused `net_scan` went back as
    // `{ok: false, error: "<scope reason>…"}` and the server's echo of it was
    // `{"ok": false, "summary": "", "output": "", "artifacts": []}` — our
    // `error` was dropped entirely. So the card had nothing to show (0.4f) and,
    // worse, the tool_result handed to the model read "net_scan completed on
    // device.", which is why it then reported a successful scan of a host it
    // never touched. Successful calls in the same capture kept their summary
    // intact, so `summary` is the field that survives.
    final reason = result.summary ??
        (result.ok ? 'Done' : (result.error ?? 'Failed'));
    final summary =
        attempt > 1 ? '$reason (after $attempt attempts)' : reason;

    // Reflect locally straight away — the phone already knows the answer, so
    // waiting for the server to echo it back would add a pointless delay.
    transcript.apply(AgentToolResult(
      callId: call.callId,
      ok: result.ok,
      summary: summary,
      output: result.output,
      error: result.error,
    ));
    onChanged?.call();

    _post(DeviceToolResultMessage(
      callId: call.callId,
      ok: result.ok,
      summary: summary,
      output: result.output,
      error: result.error,
      artifacts: result.artifacts,
    ));
  }

  /// Sends a device result and remembers it, so a replayed `tool_call` can be
  /// answered from what already happened instead of happening again.
  void _post(DeviceToolResultMessage message) {
    _completedCalls[message.callId] = message;
    _outbox.enqueue(message);
  }

  // ── Outbound ───────────────────────────────────────────────────────────

  /// Answers an approval prompt.
  ///
  /// The transcript updates immediately and the message goes to the outbox
  /// for guaranteed delivery. Optimism is deliberate: leaving the card on
  /// "needs approval" while the response is in flight reads as a dead
  /// button, and the outbox surfaces the truth if delivery actually fails.
  OutboxEntry respondToApproval(
    String callId, {
    required ApprovalDecision decision,
    Map<String, dynamic>? editedInput,
  }) {
    switch (decision) {
      case ApprovalDecision.deny:
        transcript.markDenied(callId);
      case ApprovalDecision.approve:
      case ApprovalDecision.approveForSession:
        transcript.markApproved(callId, editedInput: editedInput);
    }
    onChanged?.call();

    return _outbox.enqueue(ApprovalResponseMessage(
      callId: callId,
      decision: decision,
      editedInput: editedInput,
    ));
  }

  /// Stops one tool, or the whole run when [callId] is null.
  ///
  /// The card is *not* marked cancelled here — the server decides whether the
  /// stop landed, and a tool that completes in the same instant should show
  /// its result. `run_finished` sweeps anything still active.
  OutboxEntry cancel({String? callId}) {
    // Stop local work immediately — a scan running on this phone should not
    // keep burning radio while a cancel travels to the server and back.
    if (callId != null) deviceExecutor?.cancel(callId);
    return _outbox.enqueue(CancelMessage(callId: callId));
  }

  /// Asks the server to replay everything after the last frame we folded in.
  ///
  /// Returns null when resume isn't possible — no run id yet, or nothing
  /// received to resume from. Callers should start a fresh run instead of
  /// treating that as an error.
  OutboxEntry? resume() {
    final id = runId;
    final from = transcript.lastSeq;
    if (id == null || from == null) return null;
    return _outbox.enqueue(ResumeMessage(runId: id, fromSeq: from));
  }

  /// Points the session at a new transport after a reconnect, then replays
  /// anything undelivered and requests the missed frames.
  void rebind(AgentControlChannel channel) {
    _channel = channel;
    _outbox.rebind(channel);
    resume();
  }

  void retryFailedControl() => _outbox.retryFailed();

  void clear() {
    transcript.clear();
    runId = null;
    _outbox.pruneDelivered();
    onChanged?.call();
  }

  void dispose() => _outbox.dispose();
}
