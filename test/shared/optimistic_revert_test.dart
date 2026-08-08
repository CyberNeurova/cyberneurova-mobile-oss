import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/shared/collections/optimistic_revert.dart';

void main() {
  group('restoreAt', () {
    test('puts the row back where it was', () {
      expect(restoreAt(['a', 'c'], 'b', 1), ['a', 'b', 'c']);
      expect(restoreAt(['b', 'c'], 'a', 0), ['a', 'b', 'c']);
    });

    test('keeps everything else that is in the list now', () {
      // The whole point: the list has moved on since the row was removed, and
      // those changes must survive the revert.
      expect(restoreAt(['new', 'c'], 'b', 1), ['new', 'b', 'c']);
    });

    test('an index past the end appends rather than throwing', () {
      // The list can be shorter by the time a failure lands — other rows may
      // have gone too. Best-effort placement, never a crash.
      expect(restoreAt(['a'], 'z', 9), ['a', 'z']);
      expect(restoreAt(<String>[], 'z', 3), ['z']);
    });

    test('a negative index lands at the front', () {
      expect(restoreAt(['a'], 'z', -1), ['z', 'a']);
    });

    test('does not mutate the list it was given', () {
      final original = ['a', 'c'];
      restoreAt(original, 'b', 1);
      expect(original, ['a', 'c']);
    });
  });

  group('positionOf', () {
    test('finds the row', () {
      expect(positionOf(['a', 'b', 'c'], (v) => v == 'b'), 1);
    });

    test('returns -1 when the row is gone', () {
      // Call sites bail on this: a row that is no longer there was already
      // removed by something else, and putting it back would resurrect it.
      expect(positionOf(['a'], (v) => v == 'zz'), -1);
    });
  });
}
