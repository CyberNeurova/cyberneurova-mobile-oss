import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/memory/data/models/memory_model.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  return MemoryRepository(ref.watch(apiClientProvider));
});

class MemoryRepository {
  MemoryRepository(this._client);
  final ApiClient _client;

  Future<MemoryListResponse> listMemories({String? cursor}) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.MEMORY,
      queryParameters: {
        'limit': 100,
        if (cursor != null) 'startingAfter': cursor,
      },
    );
    final data = res.data!;
    return MemoryListResponse.fromJson(data);
  }

  Future<void> deleteOne(String id) async {
    await _client.delete(ApiConstants.memoryById(id));
  }

  Future<void> clearAll() async {
    await _client.delete(ApiConstants.MEMORY);
  }
}
