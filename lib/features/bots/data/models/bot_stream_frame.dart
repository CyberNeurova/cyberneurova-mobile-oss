import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/coerce.dart';

/// The multiplexed `/bot/stream` SSE frames (BOT_SECTION_API.md §4). ONE
/// stream carries events for every room the user belongs to — demux by
/// `roomId`, never open one stream per room.
///
/// Same three parsing rules as [AgentFrame]: unknown types are ignored (a new
/// server frame must not break shipped apps), every field is defensively
/// typed, and unknown fields are preserved on the source map where relevant.
sealed class BotStreamEvent {
  const BotStreamEvent();

  /// Parses one SSE `data:` payload. [eventName] is the SSE `event:` line,
  /// used as a fallback when the payload omits `type`.
  static BotStreamEvent? tryParse(
    Map<String, dynamic> data, {
    String? eventName,
  }) {
    final type = asString(data['type']) ?? eventName;
    switch (type) {
      case 'ready':
        return BotReady(userId: asString(data['userId']));

      case 'message':
        final message = BotMessage.tryParse(data['message']);
        final roomId = asString(data['roomId']) ?? message?.roomId;
        if (message == null || roomId == null) return null;
        return BotMessageEvent(roomId: roomId, message: message);

      case 'run':
        final roomId = asString(data['roomId']);
        final runId = asString(data['runId']);
        if (roomId == null || runId == null) return null;
        return BotRunEvent(
          roomId: roomId,
          runId: runId,
          status: asString(data['status']),
        );

      case 'command':
        final roomId = asString(data['roomId']);
        final commandId = asString(data['commandId']);
        if (roomId == null || commandId == null) return null;
        return BotCommandEvent(
          roomId: roomId,
          commandId: commandId,
          kind: asString(data['kind']),
          runId: asString(data['runId']),
        );

      case 'presence':
        return BotPresenceEvent(
          userId: asString(data['userId']),
          deviceId: asString(data['deviceId']),
          status: asString(data['status']),
          role: asString(data['role']),
        );

      case 'ping':
        return const BotPing();
    }
    return null;
  }
}

/// Sent once on connect.
final class BotReady extends BotStreamEvent {
  const BotReady({this.userId});
  final String? userId;
}

/// A message landed in [roomId]. Apply after de-duping on `message.seq`.
final class BotMessageEvent extends BotStreamEvent {
  const BotMessageEvent({required this.roomId, required this.message});
  final String roomId;
  final BotMessage message;
}

/// A run's status changed (P2 renders this; P1 can ignore it).
final class BotRunEvent extends BotStreamEvent {
  const BotRunEvent({required this.roomId, required this.runId, this.status});
  final String roomId;
  final String runId;
  final String? status;
}

/// A remote enqueued an up-lane command (wakes the desktop authority; P3).
final class BotCommandEvent extends BotStreamEvent {
  const BotCommandEvent({
    required this.roomId,
    required this.commandId,
    this.kind,
    this.runId,
  });
  final String roomId;
  final String commandId;
  final String? kind;
  final String? runId;
}

/// One of the user's devices heartbeated online/offline.
final class BotPresenceEvent extends BotStreamEvent {
  const BotPresenceEvent({this.userId, this.deviceId, this.status, this.role});
  final String? userId;
  final String? deviceId;
  final String? status;
  final String? role;
}

/// Keepalive (~25s). Ignore.
final class BotPing extends BotStreamEvent {
  const BotPing();
}
