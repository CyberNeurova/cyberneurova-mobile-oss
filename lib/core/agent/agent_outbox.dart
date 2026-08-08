import 'dart:async';

import 'package:cyberneurova_mobile/core/agent/agent_control.dart';

/// Delivery state of one queued control message.
enum OutboxStatus { queued, sending, delivered, failed }

class OutboxEntry {
  OutboxEntry(this.message) : status = OutboxStatus.queued;

  final AgentControlMessage message;
  OutboxStatus status;
  int attempts = 0;
  Object? lastError;

  String get key => message.dedupeKey;
}

/// Reliable, ordered delivery of control messages.
///
/// Exists because of one asymmetry: inbound frames are a stream the server
/// can replay, but an outbound approval is the *only* thing that unblocks a
/// paused run. If it is dropped on a flaky connection and never retried, the
/// run waits forever and the user sees a card stuck on "needs approval" with
/// no way to recover.
///
/// So: messages queue, send in order, and retry with exponential backoff.
/// Every control message names a specific `call_id` or `seq` and is therefore
/// idempotent server-side, which is what makes blind retry safe.
///
/// Pure Dart with an injectable [delay] so the backoff schedule is testable
/// without real waiting.
class AgentOutbox {
  AgentOutbox({
    required AgentControlChannel channel,
    Future<void> Function(Duration)? delay,
    this.maxAttempts = 5,
    this.onChanged,
  })  : _channel = channel,
        _delay = delay ?? Future<void>.delayed;

  AgentControlChannel _channel;
  final Future<void> Function(Duration) _delay;

  /// After this many failures a message is marked [OutboxStatus.failed] and
  /// the UI surfaces it. Five attempts spans roughly 15 seconds of backoff,
  /// which covers a tunnel or a handover without leaving the user waiting.
  final int maxAttempts;

  /// Fired whenever an entry changes state, so a provider can rebuild.
  final void Function()? onChanged;

  final List<OutboxEntry> _entries = [];
  bool _draining = false;
  bool _disposed = false;

  List<OutboxEntry> get entries => List.unmodifiable(_entries);

  bool get hasUndelivered =>
      _entries.any((e) => e.status != OutboxStatus.delivered);

  bool get hasFailures => _entries.any((e) => e.status == OutboxStatus.failed);

  /// Swaps the transport — used when a session reconnects on a new channel.
  /// Anything still queued is retried on the new one.
  void rebind(AgentControlChannel channel) {
    _channel = channel;
    for (final e in _entries) {
      if (e.status == OutboxStatus.failed) {
        e
          ..status = OutboxStatus.queued
          ..attempts = 0;
      }
    }
    unawaited(_drain());
  }

  /// Queues [message]. Returns the entry so a caller can watch its status.
  ///
  /// A message with the same [AgentControlMessage.dedupeKey] as an
  /// undelivered one replaces it rather than queueing twice — re-tapping
  /// Approve, or a second resume after a flapping connection, must not
  /// produce two sends.
  OutboxEntry enqueue(AgentControlMessage message) {
    final existingIndex =
        _entries.indexWhere((e) => e.key == message.dedupeKey);
    if (existingIndex >= 0) {
      final existing = _entries[existingIndex];
      if (existing.status == OutboxStatus.sending) {
        // Mid-flight: let it finish, then queue the replacement behind it.
        final entry = OutboxEntry(message);
        _entries.add(entry);
        unawaited(_drain());
        return entry;
      }
      final entry = OutboxEntry(message);
      _entries[existingIndex] = entry;
      unawaited(_drain());
      return entry;
    }
    final entry = OutboxEntry(message);
    _entries.add(entry);
    unawaited(_drain());
    return entry;
  }

  /// Retries everything that gave up, e.g. after connectivity returns.
  void retryFailed() {
    var changed = false;
    for (final e in _entries) {
      if (e.status == OutboxStatus.failed) {
        e
          ..status = OutboxStatus.queued
          ..attempts = 0
          ..lastError = null;
        changed = true;
      }
    }
    if (changed) {
      onChanged?.call();
      unawaited(_drain());
    }
  }

  /// Sends queued messages one at a time, in order.
  ///
  /// Ordering is not cosmetic: an approval must reach the server before a
  /// cancel for the same run, or the server sees them inverted.
  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (!_disposed) {
        final entry = _nextQueued();
        if (entry == null) break;

        entry.status = OutboxStatus.sending;
        onChanged?.call();

        try {
          await _channel.send(entry.message);
          if (_disposed) return;
          entry.status = OutboxStatus.delivered;
          onChanged?.call();
        } catch (e) {
          if (_disposed) return;
          entry
            ..attempts += 1
            ..lastError = e;

          if (entry.attempts >= maxAttempts) {
            entry.status = OutboxStatus.failed;
            onChanged?.call();
            // Stop draining: with the channel evidently down, hammering the
            // rest of the queue just burns attempts. `rebind` or
            // `retryFailed` restarts it.
            break;
          }

          entry.status = OutboxStatus.queued;
          onChanged?.call();
          await _delay(_backoffFor(entry.attempts));
          if (_disposed) return;
        }
      }
    } finally {
      _draining = false;
    }
  }

  OutboxEntry? _nextQueued() {
    for (final e in _entries) {
      if (e.status == OutboxStatus.queued) return e;
    }
    return null;
  }

  /// 250ms, 500ms, 1s, 2s, 4s — capped so a long outage doesn't push the
  /// last attempt minutes out, by which point the user has moved on.
  Duration _backoffFor(int attempts) {
    final ms = 250 * (1 << (attempts - 1).clamp(0, 4));
    return Duration(milliseconds: ms.clamp(250, 4000));
  }

  /// Drops delivered entries so the queue doesn't grow across a long session.
  void pruneDelivered() {
    final before = _entries.length;
    _entries.removeWhere((e) => e.status == OutboxStatus.delivered);
    if (_entries.length != before) onChanged?.call();
  }

  void dispose() {
    _disposed = true;
    _entries.clear();
  }
}
