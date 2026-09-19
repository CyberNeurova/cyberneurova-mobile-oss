import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/billing_models.dart';

void main() {
  group('PaymentHistoryResponse.fromJson', () {
    test('parses the {success, payments, count} contract', () {
      final resp = PaymentHistoryResponse.fromJson({
        'success': true,
        'payments': [
          {
            'invoiceId': 'inv1',
            'tier': 'pro',
            'amount': 120,
            'currency': 'USD',
            'status': 'paid',
            'paymentMethod': 'crypto',
            'createdAt': '2026-06-01T00:00:00.000Z',
          },
        ],
        'count': 1,
      });
      expect(resp.payments, hasLength(1));
      expect(resp.payments.single.id, 'inv1'); // from invoiceId
      expect(resp.payments.single.amount, 120);
    });

    test('coerces amount as string or Mongo Decimal128 (no crash)', () {
      final resp = PaymentHistoryResponse.fromJson({
        'payments': [
          {'invoiceId': 'a', 'tier': 'pro', 'status': 'paid', 'amount': '99.50'},
          {
            'invoiceId': 'b',
            'tier': 'premium',
            'status': 'paid',
            'amount': {r'$numberDecimal': '49.00'},
          },
        ],
      });
      expect(resp.payments.map((p) => p.amount).toList(), [99.50, 49.00]);
    });

    test('a single malformed row is skipped, not fatal to the whole list', () {
      final resp = PaymentHistoryResponse.fromJson({
        'payments': [
          {'invoiceId': 'ok', 'tier': 'pro', 'status': 'paid', 'amount': 10},
          'not-a-map',
          {'amount': null, 'status': null}, // missing/odd fields → defaulted
        ],
      });
      // Before the fix one bad row threw and the History screen errored out.
      expect(resp.payments.length, greaterThanOrEqualTo(1));
      expect(resp.payments.first.id, 'ok');
    });

    test('tolerates a data-enveloped payload', () {
      final resp = PaymentHistoryResponse.fromJson({
        'success': true,
        'data': {
          'payments': [
            {'invoiceId': 'x', 'tier': 'pro', 'status': 'paid', 'amount': 5},
          ],
        },
      });
      expect(resp.payments.single.id, 'x');
    });

    test('empty / missing never throws', () {
      expect(PaymentHistoryResponse.fromJson({}).payments, isEmpty);
      expect(
          PaymentHistoryResponse.fromJson({'payments': null}).payments, isEmpty);
    });
  });

  group('PlansResponse.fromJson promotion', () {
    test('tolerates a fractional promo discountPercent', () {
      // Before the fix, 12.5 hit the generated `discountPercent as int?` and
      // threw, erroring the whole Plans/upgrade screen for every user.
      final res = PlansResponse.fromJson({
        'monthly': <dynamic>[],
        'yearly': <dynamic>[],
        'promotion': {'title': 'Spring', 'discountPercent': 12.5},
      });
      expect(res.monthly, isEmpty);
      expect(res.promotion, isNotNull);
      expect(res.promotion!.title, 'Spring');
      expect(res.promotion!.discountPercent, anyOf(0, 12));
    });

    test('tolerates an epoch-number promo expiresAt', () {
      final res = PlansResponse.fromJson({
        'monthly': <dynamic>[],
        'promotion': {'expiresAt': 1737300000000},
      });
      expect(res.promotion, isNotNull);
      expect(res.promotion!.expiresAt, isNull);
    });

    test('a non-map promotion drops the banner, never the screen', () {
      final res = PlansResponse.fromJson({
        'monthly': <dynamic>[],
        'promotion': 'nope',
      });
      expect(res.promotion, isNull);
    });

    test('a well-formed promotion still parses', () {
      final res = PlansResponse.fromJson({
        'monthly': <dynamic>[],
        'promotion': {
          'title': 'Launch',
          'discountPercent': 20,
          'expiresAt': '2026-12-31T00:00:00.000Z',
        },
      });
      expect(res.promotion!.discountPercent, 20);
      expect(res.promotion!.expiresAt, isNotNull);
    });
  });
}
