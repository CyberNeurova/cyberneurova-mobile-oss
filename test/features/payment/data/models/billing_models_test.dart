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
}
