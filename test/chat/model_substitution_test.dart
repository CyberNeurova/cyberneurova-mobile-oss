import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/model_provider.dart';

void main() {
  group('modelSubstitutionReason', () {
    test('says nothing when the pick is what answers', () {
      expect(modelSubstitutionReason(ModelSubstitution.none), isNull);
    });

    test('says nothing for a local route — the pick does not apply', () {
      expect(modelSubstitutionReason(ModelSubstitution.localRoute), isNull);
    });

    test('explains the free tier', () {
      final r = modelSubstitutionReason(ModelSubstitution.freeTier);
      expect(r, isNotNull);
      expect(r, contains('free plan'));
    });

    test('explains a locked model without discarding the choice', () {
      final r = modelSubstitutionReason(ModelSubstitution.lockedForTier);
      expect(r, isNotNull);
      expect(r, contains('upgrade'));
    });

    test('every substituting case has a reason', () {
      for (final s in ModelSubstitution.values) {
        final substituting = s == ModelSubstitution.freeTier ||
            s == ModelSubstitution.lockedForTier;
        expect(
          modelSubstitutionReason(s) != null,
          substituting,
          reason: '$s must ${substituting ? '' : 'not '}carry a reason',
        );
      }
    });
  });
}
