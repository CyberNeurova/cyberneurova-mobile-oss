import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/shared/time/record_time.dart';

void main() {
  DateTime ago(Duration d) => DateTime.now().subtract(d);

  group('recordTime', () {
    test('recent times stay relative, because that is what people want', () {
      expect(recordTime(ago(const Duration(seconds: 5))), 'just now');
      expect(recordTime(ago(const Duration(minutes: 5))), '5m ago');
      expect(recordTime(ago(const Duration(hours: 3))), '3h ago');
      expect(recordTime(ago(const Duration(days: 3))), '3d ago');
    });

    test('anything older resolves to an unambiguous date', () {
      // The bug this replaces: the sessions screen rendered `M/D/YYYY`, which
      // is US-only, on a screen where reading the date wrong is the difference
      // between "that was me last week" and "that was not me".
      final old = DateTime(2026, 7, 27, 13, 45);
      expect(recordTime(old), '2026-07-27');
      expect(recordTime(ago(const Duration(days: 8))),
          matches(r'^\d{4}-\d{2}-\d{2}$'));
    });

    test('never renders month/day/year', () {
      final old = DateTime(2026, 7, 27);
      final v = recordTime(old);
      expect(v, isNot(contains('/')));
      expect(v, startsWith('2026-'));
    });

    test('a missing timestamp says what the caller asked it to', () {
      expect(recordTime(null), '');
      expect(recordTime(null, ifNull: 'recently'), 'recently');
    });

    test('a future timestamp does not become "just now"', () {
      // Clock skew between phone and server is normal; claiming a session was
      // used "just now" when the stamp is tomorrow would be worse than a date.
      final future = DateTime.now().add(const Duration(days: 2));
      expect(recordTime(future), matches(r'^\d{4}-\d{2}-\d{2}$'));
    });

    test('the boundary at a week lands on the date, not "7d ago"', () {
      expect(recordTime(ago(const Duration(days: 6, hours: 23))), '6d ago');
      expect(recordTime(ago(const Duration(days: 7, hours: 1))),
          matches(r'^\d{4}-\d{2}-\d{2}$'));
    });
  });

  group('isoDate', () {
    test('pads month and day', () {
      expect(isoDate(DateTime(2026, 1, 2)), '2026-01-02');
      expect(isoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
