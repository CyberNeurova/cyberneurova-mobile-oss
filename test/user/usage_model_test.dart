import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/user/data/models/usage_model.dart';

/// The path UserRepository.getUsage takes.
UsageDetail parse(Map<String, dynamic> json) =>
    UsageDetail.fromJson(UsageDetail.sanitize(json));

void main() {
  group('UsageDetail.sanitize', () {
    test('a well-formed v2 payload parses unchanged', () {
      final u = parse({
        'schemaVersion': 2,
        'tier': 'pro',
        'billingCycle': 'yearly',
        'legacy': false,
        'session': {
          'used': 1200,
          'limit': 50000,
          'remaining': 48800,
          'percentUsed': 2.4,
          'resetAt': '2026-10-01T18:00:00.000Z',
        },
        'weekly': {'used': 2400000, 'limit': 1400000000},
        'extraUnits': {
          'remaining': 10,
          'spentUsdThisMonth': 4.5,
          'autoReload': true,
          'monthResetAt': '2026-11-01T00:00:00.000Z',
        },
        'tierReference': {'tokensPerPeriod': 1400000000},
        'message': 'ok',
      });
      expect(u.tier, 'pro');
      expect(u.billingCycle, 'yearly');
      expect(u.legacy, isFalse);
      expect(u.session!.used, 1200);
      expect(u.session!.percentUsed, 2.4);
      expect(u.session!.resetAt, DateTime.utc(2026, 10, 1, 18));
      expect(u.weekly!.limit, 1400000000);
      expect(u.extraUnits!.autoReload, isTrue);
      expect(u.extraUnits!.monthResetAt, DateTime.utc(2026, 11));
      expect(u.tierReference!.tokensPerPeriod, 1400000000);
      expect(u.message, 'ok');
    });

    test('a fractional count still truncates, an int percent still reads', () {
      // Already tolerated by the generated `(as num?)?.toInt()`; pinned so the
      // sanitizer does not regress it.
      final u = parse({
        'weekly': {'used': 2400000.5, 'limit': 1400000000, 'percentUsed': 50},
      });
      expect(u.weekly!.used, 2400000);
      expect(u.weekly!.percentUsed, 50.0);
    });

    test('a numeric string count is read', () {
      final u = parse({
        'weekly': {'used': '2400000', 'limit': ' 1400000000 '},
      });
      expect(u.weekly!.used, 2400000);
      expect(u.weekly!.limit, 1400000000);
    });

    test('an epoch resetAt drops the date and keeps the bucket', () {
      // Seconds or milliseconds is a guess; no date beats a wrong one.
      final u = parse({
        'session': {'used': 7, 'resetAt': 1737300000000},
        'extraUnits': {'monthResetAt': 'next month'},
      });
      expect(u.session!.used, 7);
      expect(u.session!.resetAt, isNull);
      expect(u.extraUnits!.monthResetAt, isNull);
    });

    test('a bucket that is not an object is dropped, the rest survives', () {
      final u = parse({
        'session': 'oops',
        'weekly': {'used': 5, 'limit': 10},
        'weeklyPremium': [1, 2],
        'tierReference': 0,
      });
      expect(u.session, isNull);
      expect(u.weeklyPremium, isNull);
      expect(u.tierReference, isNull);
      expect(u.weekly!.used, 5);
    });

    test('wrong-typed scalars fall back to their own defaults', () {
      final u = parse({
        'schemaVersion': 'two',
        'tier': 5,
        'billingCycle': null,
        'legacy': 'yes',
        'message': 42,
        'weekly': {'used': true, 'limit': double.nan, 'percentUsed': 'half'},
      });
      expect(u.schemaVersion, 2);
      expect(u.tier, 'free');
      expect(u.billingCycle, 'monthly');
      expect(u.legacy, isFalse);
      expect(u.message, isNull);
      expect(u.weekly!.used, 0);
      expect(u.weekly!.limit, 0);
      expect(u.weekly!.percentUsed, 0.0);
    });

    test('a legacy account is still reported as legacy', () {
      expect(parse({'schemaVersion': 1, 'legacy': true}).legacy, isTrue);
    });

    test('a garbled v2 payload never throws and never reads as legacy', () {
      // The screen picks the legacy "Tokens 0 / 60M" card on
      // `valueOrNull?.legacy ?? true`, so a throw here used to swap a v2
      // account's real breakdown for the counter it is not filling.
      final garbled = <String, dynamic>{
        'schemaVersion': <String, dynamic>{},
        'tier': <dynamic>[],
        'billingCycle': 3.5,
        'legacy': null,
        'session': {'used': 'x', 'resetAt': <String, dynamic>{}},
        'weekly': {'percentUsed': <dynamic>[], 'resetAt': 12},
        'weeklyPremium': 'none',
        'extraUnits': {'autoReload': 'on', 'spentUsdLifetime': '1e400'},
        'tierReference': {'tokensPerPeriod': <String, dynamic>{}},
      };
      expect(() => parse(garbled), returnsNormally);
      final u = parse(garbled);
      expect(u.legacy, isFalse);
      expect(u.session!.used, 0);
      expect(u.extraUnits!.spentUsdLifetime, 0.0);
    });
  });
}
