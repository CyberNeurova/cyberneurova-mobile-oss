import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';

void main() {
  group('isTechnicalErrorMessage', () {
    test('catches the one that shipped', () {
      // A failed image generation rendered exactly this under a red icon.
      expect(isTechnicalErrorMessage('fetch failed'), isTrue);
      expect(isTechnicalErrorMessage('Fetch failed.'), isTrue);
    });

    test('catches the rest of the runtime-noise family', () {
      for (final m in [
        'Failed to fetch',
        'network error',
        'socket hang up',
        'load failed',
        'bad gateway',
        'undefined',
        'null',
        'connect ECONNREFUSED 127.0.0.1:9095',
        'getaddrinfo ENOTFOUND api.internal',
        'read ETIMEDOUT',
        'ERR_STREAM_PREMATURE_CLOSE',
        'TypeError: Cannot read properties of undefined',
        'SocketException: Connection reset by peer',
        'Exception: something blew up',
        // Dart ERRORS, added 2026-08-05. The list above was the Exception
        // family and stopped there, so these walked straight through — found
        // when a StateError reached the Linux-install screen and rendered
        // "Bad state: Bad state: stream already listened to", the prefix
        // doubled because toString() adds its own. These are what a crash
        // path produces, and they were the least presentable of the lot.
        'Bad state: stream already listened to',
        'RangeError (index): Invalid value: Not in inclusive range 0..3: 7',
        'Null check operator used on a null value',
        "type 'Null' is not a subtype of type 'String'",
        'NoSuchMethodError: The getter was called on null',
        'Concurrent modification during iteration',
        'Invalid argument(s): No host specified',
        'Unsupported operation: Cannot add to an unmodifiable list',
      ]) {
        expect(isTechnicalErrorMessage(m), isTrue, reason: m);
      }
    });

    test('empty or whitespace is not a message', () {
      expect(isTechnicalErrorMessage(''), isTrue);
      expect(isTechnicalErrorMessage('   '), isTrue);
    });

    test('KEEPS real server messages — this is the expensive mistake', () {
      // Discarding these would be worse than the bug being fixed: they are
      // the ones that tell the user what to actually do.
      for (final m in [
        '8.8.8.8 is outside the authorized scope for this session.',
        'Your daily image limit resets at midnight.',
        'This chat is not available on your account.',
        'Upgrade your plan for higher limits.',
        'The prompt was blocked by the safety filter.',
        'Session expired. Please sign in again.',
        // Near misses for the Dart-Error tokens added 2026-08-05. Each shares
        // words with a runtime prefix but is a sentence a person wrote, and
        // the tokens are deliberately shaped to let them through: the colon
        // in "Bad state:", the parentheses in "Invalid argument(s)", and the
        // exact word order of "Unsupported operation:".
        'The upload is in a bad state and needs retrying.',
        'Invalid argument provided for the aspect ratio.',
        'This operation is unsupported on your current plan.',
        'The range you selected is too large.',
      ]) {
        expect(isTechnicalErrorMessage(m), isFalse, reason: m);
      }
    });

    test('a sentence that merely mentions a network is kept', () {
      // "network" alone must not trip it — only the bare whole-message form.
      expect(
        isTechnicalErrorMessage(
            'We could not reach your local network from this session.'),
        isFalse,
      );
    });
  });
}
