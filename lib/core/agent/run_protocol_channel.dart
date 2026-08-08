import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';

/// Sends the device's half of a run back to the server.
///
/// ## Why this is not [HttpAgentControlChannel]
///
/// That one posts every message to a single path, which was right when the
/// run protocol was a sketch. The deployed shape splits them: a tool result
/// goes to `/agent/device_result`, everything else to `/agent/control`, and
/// both need the `run_id` the client learned from the frames rather than the
/// `type` field the client used to carry.
///
/// Translating here rather than changing the message classes keeps the wire
/// format in one file. The transcript, the outbox and its dedupe key all key
/// on `call_id` and do not care how it is addressed.
class RunProtocolChannel implements AgentControlChannel {
  RunProtocolChannel({
    required ApiClient client,
    required this.runId,
  }) : _client = client;

  final ApiClient _client;

  /// Learned from the first frame that carried it.
  ///
  /// A message sent before any frame has arrived has nothing to address, and
  /// posting it without one would be silently dropped server-side — so it
  /// throws instead, and the outbox retries once the run identifies itself.
  final String? Function() runId;

  @override
  bool get isConnected => true;

  @override
  Future<void> send(AgentControlMessage message) async {
    try {
      await _send(message);
    } catch (e) {
      // Kept rather than removed after debugging. A failed delivery shows the
      // user "Couldn't reach the agent" and nothing else, and the one time it
      // happened on prod it could not be reproduced afterwards — tool calls
      // only parse on a minority of runs, so the window to catch it is small.
      // Without this line the next occurrence is equally undiagnosable.
      debugPrint('[runproto] send failed: '
          '${message.dedupeKey} -> ${_describe(e)}');
      rethrow;
    }
  }

  /// The status and body if this was an HTTP failure, else the error itself.
  static String _describe(Object e) {
    if (e is DioException) {
      final r = e.response;
      if (r != null) return 'HTTP ${r.statusCode} ${r.data}';
      return '${e.type} ${e.message}';
    }
    return '$e';
  }

  Future<void> _send(AgentControlMessage message) async {
    final id = runId();
    if (id == null || id.isEmpty) {
      // The outbox retries, so a message sent before the run has identified
      // itself is delayed rather than lost.
      throw const AgentControlUnavailable();
    }

    final json = message.toJson();
    final type = json['type'];

    if (type == 'device_tool_result') {
      debugPrint('[runproto] POST ${ApiConstants.AGENT_DEVICE_RESULT} '
          'run=$id call=${json['call_id']} ok=${json['ok']}');
      await _client.post<Map<String, dynamic>>(
        ApiConstants.AGENT_DEVICE_RESULT,
        data: {
          'run_id': id,
          'call_id': json['call_id'],
          'ok': json['ok'],
          'summary': json['summary'] ?? '',
          'output': json['output'] ?? '',
          'artifacts': json['artifacts'] ?? const <Object>[],
        },
      );
      return;
    }

    await _client.post<Map<String, dynamic>>(
      ApiConstants.AGENT_CONTROL,
      data: {
        'run_id': id,
        'action': _actionFor(type as String?, json),
        if (json['call_id'] != null) 'call_id': json['call_id'],
      },
    );
  }

  /// Maps our message vocabulary onto the server's `action` field.
  ///
  /// An approval carries a three-valued decision; the server takes two
  /// actions. Deny becomes cancel, and approve-for-session is still an
  /// approval of THIS call — the session-wide part is remembered on our side.
  /// Getting this backwards would approve what the user denied, so it is
  /// spelled out rather than derived.
  static String _actionFor(String? type, Map<String, dynamic> json) {
    switch (type) {
      case 'approval_response':
        return json['decision'] == 'deny' ? 'cancel' : 'approve';
      case 'cancel':
        return 'cancel';
      case 'resume':
        return 'resume';
      default:
        return type ?? 'resume';
    }
  }
}
