import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/features/research/data/models/research_models.dart';

final researchRepositoryProvider = Provider<ResearchRepository>((ref) {
  return ResearchRepository(ref.watch(apiClientProvider));
});

/// Wraps `/api/mobile/v1/research/*`. Starting a new thread still goes
/// through `/chat` (`POST /chat` with `section: "research"` + `category`,
/// then `/chat/:id/complete` as normal) — there's no dedicated mobile
/// streaming endpoint for research yet.
class ResearchRepository {
  ResearchRepository(this._client);
  final ApiClient _client;

  static const String _base = '/research/sessions';

  Future<ResearchListResponse> list({
    String? category,
    int limit = 20,
    String? cursor,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      _base,
      queryParameters: {
        if (category != null && category.isNotEmpty) 'category': category,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return ResearchListResponse.fromJson(res.data!);
  }

  Future<ResearchDetail> get(String id) async {
    final res = await _client.get<Map<String, dynamic>>('$_base/$id');
    return ResearchDetail.fromApi(res.data!);
  }

  Future<void> delete(String id) async {
    await _client.delete('$_base/$id');
  }
}
