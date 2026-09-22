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

    test('drops a query with a non-object source instead of crashing', () {
      // whereType skipped non-map query ELEMENTS, but a map query whose nested
      // `sources` element is a bare string still threw `String as Map` inside
      // the generated fromJson and blanked the detail screen.
      final d = ResearchDetail.fromApi({
        'session': {
          'id': 's',
          'queries': [
            {
              'id': 'q1',
              'sources': ['https://x'],
            },
            {'id': 'q2'},
          ],
        },
      });
      expect(d.queries.map((q) => q.id), contains('q2'));
    });
  });

  group('ResearchListResponse.fromJson', () {
    test('drops a malformed row instead of failing the whole list', () {
      // Row 'a' has an epoch-number createdAt: the generated fromJson parses it
      // as a String and throws. whereType let it through (it IS a map); before
      // the per-row guard that one row errored the entire research list.
      final res = ResearchListResponse.fromJson({
        'sessions': [
          {'sessionId': 'a', 'createdAt': 1737300000000},
          {'sessionId': 'b', 'title': 'ok'},
        ],
      });
      expect(res.sessions.map((s) => s.id), contains('b'));
    });

    test('tolerates a missing / non-list sessions field', () {
      expect(ResearchListResponse.fromJson(<String, dynamic>{}).sessions,
          isEmpty);
      expect(
        ResearchListResponse.fromJson({'sessions': 'nope'}).sessions,
        isEmpty,
      );
    });
  });
}
