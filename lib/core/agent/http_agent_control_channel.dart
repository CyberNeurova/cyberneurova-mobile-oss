import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';

/// Sends control messages as plain POSTs alongside the inbound stream.
///
/// This is the simpler of the two shapes core could expose. If control moves
/// onto the same WebSocket as the frames (like `SessionsWebSocket` does for
/// the CLI), write a second [AgentControlChannel] against that socket — the
/// message bodies are identical, and nothing above this layer changes.
///
/// Throws on any non-2xx or transport failure so [AgentOutbox] retries.
/// Swallowing errors here would strand a paused run.
class HttpAgentControlChannel implements AgentControlChannel {
  HttpAgentControlChannel({
    required ApiClient client,
    required this.path,
  }) : _client = client;

  final ApiClient _client;

  /// Endpoint that accepts the control message body, e.g.
  /// `/chat/<id>/agent/control`. Owned by the caller because the run's
  /// address depends on how core ends up exposing sessions.
  final String path;

  @override
  bool get isConnected => true;

  @override
  Future<void> send(AgentControlMessage message) async {
    await _client.post<Map<String, dynamic>>(path, data: message.toJson());
  }
}
