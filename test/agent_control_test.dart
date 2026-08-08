import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_outbox.dart';
import 'package:cyberneurova_mobile/core/agent/agent_session.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';

/// Records what it was asked to send, and fails the first [failCount] sends
/// so retry behaviour is observable without real network flakiness.
class FakeChannel implements AgentControlChannel {
  FakeChannel({this.failCount = 0, this.connected = true});

  int failCount;
  bool connected;
  final List<AgentControlMessage> sent = [];
  int attempts = 0;

  @override
  bool get isConnected => connected;

  @override
  Future<void> send(AgentControlMessage message) async {
    attempts++;
    if (failCount > 0) {
      failCount--;
      throw Exception('transport down');
    }
    sent.add(message);
  }
}

/// Skips the real backoff so tests don't spend seconds waiting.
Future<void> noDelay(Duration _) async {}

void main() {
  group('control message wire format', () {
    test('approval response carries decision and edited input', () {
      const msg = ApprovalResponseMessage(
        callId: 'c1',
        decision: ApprovalDecision.approveForSession,
        editedInput: {'ports': '1-1000'},
      );
      expect(msg.toJson(), {
        'type': 'approval_response',
        'call_id': 'c1',
        'decision': 'approve_for_session',
        'input': {'ports': '1-1000'},
      });
    });

    test('unedited approval omits input entirely', () {
      const msg =
          ApprovalResponseMessage(callId: 'c1', decision: ApprovalDecision.deny);
      expect(msg.toJson().containsKey('input'), isFalse);
      expect(msg.toJson()['decision'], 'deny');
    });

    test('cancel without a call id targets the whole run', () {
      expect(const CancelMessage().toJson(), {'type': 'cancel'});
      expect(const CancelMessage(callId: 'c2').toJson(),
          {'type': 'cancel', 'call_id': 'c2'});
    });

    test('resume names the run and where to replay from', () {
      expect(const ResumeMessage(runId: 'r1', fromSeq: 42).toJson(),
          {'type': 'resume', 'run_id': 'r1', 'from_seq': 42});
    });
  });

  group('AgentOutbox', () {
    test('delivers a queued message', () async {
      final channel = FakeChannel();
      final outbox = AgentOutbox(channel: channel, delay: noDelay);

      outbox.enqueue(const CancelMessage(callId: 'c1'));
      await Future<void>.delayed(Duration.zero);

      expect(channel.sent, hasLength(1));
      expect(outbox.hasUndelivered, isFalse);
    });

    test('retries a transient failure and eventually delivers', () async {
      final channel = FakeChannel(failCount: 2);
      final outbox = AgentOutbox(channel: channel, delay: noDelay);

      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.approve));
      await _settle();

      expect(channel.attempts, 3, reason: '2 failures then success');
      expect(channel.sent, hasLength(1));
      expect(outbox.hasFailures, isFalse);
    });

    test('gives up after maxAttempts and surfaces the failure', () async {
      final channel = FakeChannel(failCount: 99);
      final outbox =
          AgentOutbox(channel: channel, delay: noDelay, maxAttempts: 3);

      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.approve));
      await _settle();

      expect(channel.attempts, 3);
      expect(outbox.hasFailures, isTrue);
      // The user must be able to see this — a lost approval pauses the run.
      expect(outbox.hasUndelivered, isTrue);
    });

    test('re-tapping approve replaces rather than double-sends', () async {
      final channel = FakeChannel(failCount: 99);
      final outbox =
          AgentOutbox(channel: channel, delay: noDelay, maxAttempts: 1);

      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.approve));
      await _settle();
      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.deny));
      await _settle();

      // Same dedupe key, so one entry — the later decision wins.
      expect(outbox.entries, hasLength(1));
    });

    test('different calls queue independently', () async {
      final channel = FakeChannel();
      final outbox = AgentOutbox(channel: channel, delay: noDelay);

      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.approve));
      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c2', decision: ApprovalDecision.deny));
      await _settle();

      expect(channel.sent, hasLength(2));
    });

    test('retryFailed re-queues after connectivity returns', () async {
      final channel = FakeChannel(failCount: 99);
      final outbox =
          AgentOutbox(channel: channel, delay: noDelay, maxAttempts: 2);

      outbox.enqueue(const CancelMessage(callId: 'c1'));
      await _settle();
      expect(outbox.hasFailures, isTrue);

      channel.failCount = 0;
      outbox.retryFailed();
      await _settle();

      expect(outbox.hasFailures, isFalse);
      expect(channel.sent, hasLength(1));
    });

    test('rebind moves pending work onto the new transport', () async {
      final dead = FakeChannel(failCount: 99);
      final outbox =
          AgentOutbox(channel: dead, delay: noDelay, maxAttempts: 2);

      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.approve));
      await _settle();
      expect(outbox.hasFailures, isTrue);

      final fresh = FakeChannel();
      outbox.rebind(fresh);
      await _settle();

      expect(fresh.sent, hasLength(1));
      expect(outbox.hasUndelivered, isFalse);
    });

    test('sends in order', () async {
      final channel = FakeChannel();
      final outbox = AgentOutbox(channel: channel, delay: noDelay);

      // Ordering is load-bearing: an approval must land before a cancel for
      // the same run, or the server sees them inverted.
      outbox.enqueue(const ApprovalResponseMessage(
          callId: 'c1', decision: ApprovalDecision.approve));
      outbox.enqueue(const CancelMessage(callId: 'c1'));
      await _settle();

      expect(channel.sent[0], isA<ApprovalResponseMessage>());
      expect(channel.sent[1], isA<CancelMessage>());
    });
  });

  group('AgentSession', () {
    test('approving updates the card and queues the response', () async {
      final channel = FakeChannel();
      final session = AgentSession(channel: channel, delay: noDelay);

      session.applyFrame(const AgentApprovalRequest(
        callId: 'c1',
        tool: 'Bash',
        input: {'command': 'rm x'},
      ));
      session.respondToApproval('c1',
          decision: ApprovalDecision.approve,
          editedInput: {'command': 'rm -i x'});
      await _settle();

      final card = session.transcript.items.single as ToolCardItem;
      // Optimistic: the card moves immediately rather than sitting on
      // "needs approval" while the response is in flight.
      expect(card.state, ToolCardState.running);
      expect(card.input['command'], 'rm -i x');

      final sent = channel.sent.single as ApprovalResponseMessage;
      expect(sent.callId, 'c1');
      expect(sent.editedInput, {'command': 'rm -i x'});
    });

    test('denying marks the card denied', () async {
      final channel = FakeChannel();
      final session = AgentSession(channel: channel, delay: noDelay);

      session.applyFrame(
          const AgentApprovalRequest(callId: 'c1', tool: 'Bash', input: {}));
      session.respondToApproval('c1', decision: ApprovalDecision.deny);
      await _settle();

      expect((session.transcript.items.single as ToolCardItem).state,
          ToolCardState.denied);
    });

    test('cancel leaves the card alone — the server decides', () async {
      final channel = FakeChannel();
      final session = AgentSession(channel: channel, delay: noDelay);

      session.applyFrame(
          const AgentToolCall(callId: 'c1', tool: 'Bash', input: {}));
      session.cancel(callId: 'c1');
      await _settle();

      // Still running: a tool that finishes in the same instant should show
      // its result rather than a false "cancelled".
      expect((session.transcript.items.single as ToolCardItem).state,
          ToolCardState.running);
      expect(channel.sent.single, isA<CancelMessage>());
    });

    test('resume replays from the last folded-in sequence', () async {
      final channel = FakeChannel();
      final session = AgentSession(channel: channel, delay: noDelay);

      session.applyFrame(const AgentAssistantDelta(text: 'a', seq: 7),
          frameRunId: 'run-1');
      final entry = session.resume();
      await _settle();

      expect(entry, isNotNull);
      final msg = channel.sent.single as ResumeMessage;
      expect(msg.runId, 'run-1');
      expect(msg.fromSeq, 7);
    });

    test('resume is impossible without a run id', () {
      final session = AgentSession(channel: FakeChannel(), delay: noDelay);
      session.applyFrame(const AgentAssistantDelta(text: 'a', seq: 1));
      // No run id was ever learned — callers should start fresh instead.
      expect(session.resume(), isNull);
    });

    test('rebind resends undelivered work and requests missed frames',
        () async {
      final dead = FakeChannel(failCount: 99);
      final session = AgentSession(channel: dead, delay: noDelay);

      session.applyFrame(const AgentApprovalRequest(
          callId: 'c1', tool: 'Bash', input: {}, seq: 3),
          frameRunId: 'run-1');
      session.respondToApproval('c1', decision: ApprovalDecision.approve);
      await _settle();
      expect(session.hasFailedControl, isTrue);

      final fresh = FakeChannel();
      session.rebind(fresh);
      await _settle();

      // Both the stranded approval and a resume for the missed window.
      expect(fresh.sent.whereType<ApprovalResponseMessage>(), hasLength(1));
      expect(fresh.sent.whereType<ResumeMessage>(), hasLength(1));
      expect(session.hasFailedControl, isFalse);
    });

    test('an unavailable channel reports undelivered rather than pretending',
        () async {
      final session = AgentSession(
        channel: const UnavailableControlChannel(),
        delay: noDelay,
      );

      session.applyFrame(
          const AgentApprovalRequest(callId: 'c1', tool: 'Bash', input: {}));
      session.respondToApproval('c1', decision: ApprovalDecision.approve);
      await _settle();

      expect(session.hasFailedControl, isTrue);
      expect(session.isConnected, isFalse);
    });
  });
}

/// Lets the outbox's async drain loop run to completion.
Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
