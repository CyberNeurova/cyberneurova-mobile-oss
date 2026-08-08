import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

void main() {
  group('step-limit failure text', () {
    test('says the run can carry on, not that it failed', () {
      // The wording is load-bearing: the failure bubble offers Continue only
      // when it recognises this text, and a user who is told "failed" reaches
      // for Retry — which spends the same budget getting to the same place.
      expect(kStepLimitReason, contains('step limit'));
      expect(kStepLimitReason, contains('carry on'));
      expect(kStepLimitReason.toLowerCase(), isNot(contains('try again')));
    });

    test('is a prefix match target — the bubble uses startsWith', () {
      // A run that produced prose before dying has it appended to the reason,
      // so the check has to survive extra text after it.
      const withProse = '$kStepLimitReason\n\nI created hello.py and was about '
          'to run it.';
      expect(withProse.startsWith(kStepLimitReason), isTrue);
    });

    test('is not empty and ends cleanly', () {
      expect(kStepLimitReason.trim(), kStepLimitReason);
      expect(kStepLimitReason.endsWith('.'), isTrue);
    });
  });
}
