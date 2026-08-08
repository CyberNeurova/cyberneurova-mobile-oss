import 'package:cyberneurova_mobile/features/chat/presentation/widgets/welcome_hint.dart';
import 'package:flutter_test/flutter_test.dart';

/// The failure mode is a greeting that addresses the user as "there", or
/// worse, trails a comma with nothing after it.
void main() {
  test('takes the first name', () {
    expect(firstName('Kevin Njiro'), 'Kevin');
    expect(firstName('Kevin'), 'Kevin');
  });

  test('no name at all yields null so the greeting drops the clause', () {
    expect(firstName(null), isNull);
    expect(firstName(''), isNull);
    expect(firstName('   '), isNull);
    expect(firstName('\t\n'), isNull);
  });

  test('a leading space no longer eats the name', () {
    // The old split(' ').first returned '' here, rendering "Good morning,".
    expect(firstName('  Kevin Njiro'), 'Kevin');
    expect(firstName(' Kevin'), 'Kevin');
  });

  test('collapses runs of whitespace between names', () {
    expect(firstName('Kevin   Njiro'), 'Kevin');
    expect(firstName('Kevin\tNjiro'), 'Kevin');
  });

  test('keeps a single-word name with surrounding whitespace', () {
    expect(firstName('  Kevin  '), 'Kevin');
  });
}
