import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/prompts/data/models/prompt_model.dart';

final promptRepositoryProvider = Provider<PromptRepository>((ref) {
  return PromptRepository(ref.watch(apiClientProvider));
});

class PromptRepository {
  PromptRepository(this._client);
  final ApiClient _client;

  Future<List<PromptModel>> list() async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.USER_PROMPTS,
    );
    final raw = (res.data!['prompts'] as List?) ??
        (res.data!['data'] as List?) ??
        [];
    return raw
        .whereType<Map>()
        .map((e) => PromptModel.fromJson(PromptModel.normalize(e)))
        .toList();
  }

  Future<PromptModel> create({
    required String title,
    required String content,
    String? icon,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.USER_PROMPTS,
      data: {
        // Backend requires `name` (not `title`) — sending `title` 400s.
        'name': title,
        'content': content,
        if (icon != null) 'icon': icon,
      },
    );
    return _unwrapPrompt(res.data!);
  }

  Future<PromptModel> update(
    String id, {
    String? title,
    String? content,
    String? icon,
  }) async {
    final res = await _client.patch<Map<String, dynamic>>(
      ApiConstants.userPromptById(id),
      data: {
        if (title != null) 'name': title,
        if (content != null) 'content': content,
        if (icon != null) 'icon': icon,
      },
    );
    return _unwrapPrompt(res.data!);
  }

  /// Mobile API sometimes wraps the created/updated object as `{prompt: {...}}`
  /// or `{data: {...}}` and sometimes returns it bare. Handle all three.
  PromptModel _unwrapPrompt(Map<String, dynamic> body) {
    final inner = (body['prompt'] is Map<String, dynamic>
            ? body['prompt'] as Map<String, dynamic>
            : null) ??
        (body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : null) ??
        body;
    return PromptModel.fromJson(PromptModel.normalize(inner));
  }

  Future<void> delete(String id) async {
    await _client.delete(ApiConstants.userPromptById(id));
  }
}
