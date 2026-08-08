import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/projects/data/models/project_model.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(apiClientProvider));
});

class ProjectRepository {
  ProjectRepository(this._client);
  final ApiClient _client;

  Future<List<ProjectModel>> list() async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.PROJECTS,
    );
    final raw = (res.data!['projects'] as List?) ??
        (res.data!['data'] as List?) ??
        [];
    return raw
        .whereType<Map>()
        .map((e) => ProjectModel.fromJson(ProjectModel.normalize(e)))
        .toList();
  }

  Future<ProjectModel> create({
    required String name,
    String? description,
    String? icon,
    String? color,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.PROJECTS,
      data: {
        'name': name,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
      },
    );
    return ProjectModel.fromJson(ProjectModel.normalize(res.data!));
  }

  Future<ProjectModel> update(
    String id, {
    String? name,
    String? description,
    String? icon,
    String? color,
  }) async {
    final res = await _client.patch<Map<String, dynamic>>(
      ApiConstants.projectById(id),
      data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
      },
    );
    return ProjectModel.fromJson(ProjectModel.normalize(res.data!));
  }

  Future<void> delete(String id) async {
    await _client.delete(ApiConstants.projectById(id));
  }

  Future<List<ChatModel>> getProjectChats(String projectId) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.projectChats(projectId),
    );
    final raw = (res.data!['chats'] as List?) ?? [];
    // A project listed as "1 chat" opened onto "No chats in this project"
    // (device, 2026-08-05). The count comes from `GET /projects` and the
    // contents from here, so this says which of the two is wrong: an empty
    // `chats` under a non-empty body means we are reading the wrong key.
    debugPrint('[projects] chats for $projectId: parsed=${raw.length} '
        'serverCount=${res.data!['count']} '
        'keys=${res.data!.keys.join(",")}');
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatModel.fromJson)
        .toList();
  }

  Future<void> addChatToProject(String projectId, String chatId) async {
    await _client.post(
      ApiConstants.projectChats(projectId),
      data: {'chatId': chatId},
    );
  }

  /// Bulk version — the backend API extended the endpoint to
  /// accept `chatIds: [...]` (up to 100 per call). Server fans out
  /// sequentially via coreFetch but it's still one round-trip from
  /// the client's POV, which saves ~N×400ms over the old loop.
  ///
  /// Returns the count actually added (some may fail server-side; the
  /// server returns a per-id `failed` array if any did, which the
  /// caller can surface).
  Future<({int added, List<String> failedIds})> addChatsToProject(
    String projectId,
    List<String> chatIds,
  ) async {
    if (chatIds.isEmpty) return (added: 0, failedIds: const <String>[]);
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.projectChats(projectId),
      data: {'chatIds': chatIds},
    );
    final body = res.data ?? const <String, dynamic>{};
    // Adding a chat to a project silently stored nothing (device,
    // 2026-08-05): the POST succeeded, the sheet closed, and the project was
    // still empty. This says whether `addedCount` is the key the server
    // actually uses.
    debugPrint('[projects] add ${chatIds.length} to $projectId -> '
        'status=${res.statusCode} keys=${body.keys.join(",")} '
        'addedCount=${body['addedCount']}');
    final added = (body['addedCount'] as num?)?.toInt() ?? 0;
    final failedRaw = (body['failed'] as List?) ?? const [];
    final failed = failedRaw
        .whereType<Map<String, dynamic>>()
        .map((e) => e['chatId']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return (added: added, failedIds: failed);
  }

  Future<void> removeChatFromProject(
      String projectId, String chatId) async {
    await _client.delete(
      ApiConstants.projectChats(projectId),
      data: {'chatId': chatId},
    );
  }
}
