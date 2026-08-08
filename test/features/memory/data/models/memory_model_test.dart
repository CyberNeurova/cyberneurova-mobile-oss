import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/memory/data/models/memory_model.dart';

void main() {
  group('MemoryListResponse.fromJson', () {
    test('unwraps the {success, data:{memories, tracker, …}} envelope', () {
      final resp = MemoryListResponse.fromJson({
        'success': true,
        'data': {
          'memories': [
            {'id': 'm1', 'content': 'remember this', 'category': 'fact'},
          ],
          'count': 1,
          'limit': 100,
          'tracker': {'categoryCounts': {'fact': 1}, 'atCapacity': false},
        },
      });
      expect(resp.memories, hasLength(1)); // was always empty before the fix
      expect(resp.memories.single.id, 'm1');
      expect(resp.count, 1);
      expect(resp.tracker, isNotNull);
    });

    test('tolerates a flat (un-enveloped) payload too', () {
      final resp = MemoryListResponse.fromJson({
        'memories': [
          {'id': 'm2', 'content': 'x'},
        ],
      });
      expect(resp.memories.single.id, 'm2');
    });

    test('empty / missing yields an empty list, never throws', () {
      expect(MemoryListResponse.fromJson({}).memories, isEmpty);
      expect(MemoryListResponse.fromJson({'data': {}}).memories, isEmpty);
    });
  });
}
