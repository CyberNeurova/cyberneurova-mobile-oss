import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/research/data/models/research_models.dart';

// Sahachiel: ResearchDetail.fromApi flattens the {session:{...,queries:[...]}}
// shape and used `as Map` / `as List` casts that crash the detail screen on a
// drifted payload. Lock the flatten + the defensive fallbacks.
void main() {
  group('ResearchDetail.fromApi', () {
    test('flattens the {session:{...,queries:[...]}} wrapper', () {
      final d = ResearchDetail.fromApi({
        'session': {
          'id': 's1',
          'title': 'CVE hunt',
          'category': 'cve',
          'queries': [
            {'id': 'q1', 'prompt': 'p', 'response': 'r'},
          ],
        },
      });
      expect(d.session.id, 's1');
      expect(d.session.category, 'cve');
      expect(d.queries, hasLength(1));
      expect(d.queries.first.id, 'q1');
    });

    test('treats a payload with no session wrapper as the session itself', () {
      final d = ResearchDetail.fromApi({'id': 's2', 'title': 'flat'});
      expect(d.session.id, 's2');
      expect(d.queries, isEmpty);
    });

    test('does not throw when session is a non-map', () {
      expect(
        () => ResearchDetail.fromApi({'session': 'oops'}),
        returnsNormally,
      );
    });

    test('skips non-map query elements instead of throwing', () {
      final d = ResearchDetail.fromApi({
        'session': {
          'id': 's3',
          'queries': [
            {'id': 'q1'},
            null,
            'garbage',
            {'id': 'q2'},
          ],
        },
      });
      expect(d.queries.map((q) => q.id).toList(), ['q1', 'q2']);
    });

    test('does not throw when queries is a non-list', () {
      expect(
        () => ResearchDetail.fromApi({
          'session': {'id': 's', 'queries': 'nope'},
        }),
        returnsNormally,
      );
    });
  });
}
