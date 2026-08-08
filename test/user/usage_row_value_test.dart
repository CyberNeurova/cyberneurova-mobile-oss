import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/user/data/models/usage_model.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/usage_row_value.dart';

void main() {
  group('usageRowValue', () {
    test('a v2 account shows the counter that is actually filling', () {
      // The bug: this row read the legacy counter, which stays at 0 on a v2
      // account, so a Pro user saw "0K / 60000K" after a day of heavy use.
      const usage = UsageDetail(
        weekly: UsageBucket(used: 2400000, limit: 1400000000),
      );
      expect(
        usageRowValue(usage: usage, legacyUsed: 0, legacyLimit: 60000000),
        '2.4M / 1400M',
      );
    });

    test('a legacy account still gets its own numbers', () {
      const usage = UsageDetail(legacy: true);
      expect(
        usageRowValue(usage: usage, legacyUsed: 1500, legacyLimit: 60000),
        '1.5K / 60K',
      );
    });

    test('nothing to show beats inventing a zero', () {
      expect(usageRowValue(usage: null), isNull);
      expect(
        usageRowValue(usage: null, legacyUsed: 0, legacyLimit: 0),
        isNull,
      );
    });

    test('falls back to legacy when the weekly bucket has no limit', () {
      const usage = UsageDetail(weekly: UsageBucket(used: 5, limit: 0));
      expect(
        usageRowValue(usage: usage, legacyUsed: 2000, legacyLimit: 60000),
        '2.0K / 60K',
      );
    });

    test('stays short enough for a settings row', () {
      const usage = UsageDetail(
        weekly: UsageBucket(used: 987654321, limit: 1400000000),
      );
      final v = usageRowValue(usage: usage)!;
      expect(v.length, lessThan(16), reason: v);
      expect(v, isNot(contains('60000K')));
    });
  });
}
