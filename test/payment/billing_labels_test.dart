import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/payment/presentation/screens/billing_labels.dart';

void main() {
  group('tierLabel', () {
    test('never calls a paid plan "Free"', () {
      // The owner's own billing history showed "Free · $250.00" and two
      // "Free · $15.00" rows, because the switch ended in `_ => 'Free'`.
      // There is a standing note in this project that tier maps keep omitting
      // `starter` and silently degrade paying users to free.
      expect(tierLabel('starter'), 'Starter');
      expect(tierLabel('some_new_plan'), 'Some New Plan');
      expect(tierLabel('enterprise'), 'Enterprise');
      for (final t in ['starter', 'premium', 'pro', 'pro_max', 'enterprise']) {
        expect(tierLabel(t), isNot('Free'), reason: t);
      }
    });

    test('knows the plans we ship', () {
      expect(tierLabel('free'), 'Free');
      expect(tierLabel('premium'), 'Premium');
      expect(tierLabel('pro'), 'Pro');
      expect(tierLabel('pro_max'), 'Pro Max');
    });

    test('is case and whitespace tolerant', () {
      expect(tierLabel('  PRO_MAX '), 'Pro Max');
      expect(tierLabel('Starter'), 'Starter');
    });

    test('an absent tier is not a plan name', () {
      expect(tierLabel(''), 'Plan');
      expect(tierLabel('   '), 'Plan');
    });
  });

  group('payment status', () {
    test('completed counts as paid — the chip read (0) with one on screen', () {
      for (final s in ['paid', 'completed', 'succeeded', 'success', 'PAID']) {
        expect(isPaidStatus(s), isTrue, reason: s);
        expect(statusLabel(s), 'Paid', reason: s);
      }
    });

    test('the failed bucket collects the non-payments', () {
      for (final s in ['failed', 'cancelled', 'canceled', 'expired']) {
        expect(isFailedStatus(s), isTrue, reason: s);
        expect(isPaidStatus(s), isFalse, reason: s);
      }
    });

    test('pending is neither paid nor failed', () {
      for (final s in ['pending', 'processing']) {
        expect(isPendingStatus(s), isTrue, reason: s);
        expect(isPaidStatus(s), isFalse, reason: s);
        expect(isFailedStatus(s), isFalse, reason: s);
      }
    });

    test('every status is capitalised like the others', () {
      // "completed" rendered lowercase next to "Failed" and "Cancelled".
      for (final s in ['completed', 'refunded', 'charged_back']) {
        final l = statusLabel(s);
        expect(l[0], l[0].toUpperCase(), reason: s);
      }
      expect(statusLabel('charged_back'), 'Charged Back');
      expect(statusLabel(''), 'Unknown');
    });
  });

  group('no tier switch anywhere falls back to Free', () {
    // Prove the detector still matches the real thing. A guard that has
    // quietly stopped matching reports success forever, which is worse than
    // having none.
    test('the detector catches the line that shipped', () {
      final pattern = RegExp(r"_\s*=>\s*'Free'");
      expect(pattern.hasMatch("        _ => 'Free',"), isTrue);
      expect(pattern.hasMatch('        _ => _humanise(t),'), isFalse);
    });

    test('no tier-label switch falls back to Free', () {
      // This exact idiom has now been found three times: billing history, the
      // billing RESULT screen (shown the moment a purchase completes), and the
      // standing project note that tier maps keep omitting `starter` and
      // silently degrade paying users to free.
      //
      // A grep-in-a-test is blunt, but this bug is invisible in review and
      // expensive in production: it tells someone who just paid that they are
      // on the free plan.
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        // Comments are stripped first: `billing_labels.dart` documents this
        // exact idiom while explaining why it is wrong, and a guard that
        // cannot tell code from prose fails on the file that fixes the bug.
        final src = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (!src.contains('Pro Max')) continue; // only tier-label switches
        if (RegExp(r"_\s*=>\s*'Free'").hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'tier switch falling back to Free in: $offenders');
    });
  });
}
