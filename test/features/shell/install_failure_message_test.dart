import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/providers/distro_install_provider.dart';

/// What the user is told when a Linux install fails.
///
/// This is the last line of defence on a screen that can fail in genuinely
/// technical ways — a half-downloaded rootfs, a broken tarball, no space. The
/// underlying error is often a `SocketException` or a tar exit code, and that
/// is not an explanation. It is also a long install: someone who waited
/// several minutes for it deserves a sentence they can act on.
///
/// The rule is the one used everywhere else in the app: a message written for
/// a person passes through, anything that reads like machinery is replaced.
void main() {
  test('a technical error is replaced with something actionable', () {
    for (final e in [
      Exception('SocketException: Failed host lookup'),
      StateError('Bad state: stream already listened to'),
      const FormatException('Unexpected end of input'),
    ]) {
      final msg = installFailureMessage(e);
      expect(msg, 'The download failed. Check your connection and try again.',
          reason: '$e');
    }
  });

  test('a message written for a person is kept', () {
    // The server sometimes explains the failure better than we can — an
    // out-of-space or unsupported-architecture message is worth showing.
    const human = 'Not enough storage to unpack Alpine.';
    expect(installFailureMessage(const ApiException(human)), human);
  });

  test('an AppException is read for its message, not its toString', () {
    // toString would carry the class name into the sentence.
    final msg =
        installFailureMessage(const ApiException('Server is restarting.'));
    expect(msg, 'Server is restarting.');
    expect(msg, isNot(contains('Exception')));
  });

  test('a raw exception never reaches the user verbatim', () {
    // The whole point: whatever comes back, it must not be the Dart error.
    final msg = installFailureMessage(Exception('boom'));
    expect(msg, isNot(contains('Exception')));
    expect(msg, isNot(contains('boom')));
  });
}
