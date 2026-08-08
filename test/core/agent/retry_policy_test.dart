import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/retry_policy.dart';

void main() {
  group('shouldRetryDeviceCall', () {
    test('retries a probe that timed out', () {
      // The case this exists for: a phone in a pocket loses Wi-Fi for a
      // second. Nobody should have to notice that and tap a button.
      expect(
        shouldRetryDeviceCall(
            tool: 'http_probe', error: 'Connection timed out', attempt: 1),
        isTrue,
      );
    });

    test('does not retry a command that does not exist', () {
      expect(
        shouldRetryDeviceCall(
            tool: 'file_read', error: 'no such file', attempt: 1),
        isFalse,
      );
    });

    test('never retries a tool whose repeat could do harm', () {
      // A shell_exec that failed may already have moved a file or started an
      // install. Repeating it could double-apply it, so this goes back to the
      // model, which can see the error and choose.
      for (final tool in ['shell_exec', 'apk_install', 'file_move',
        'file_delete']) {
        expect(
          shouldRetryDeviceCall(
              tool: tool, error: 'connection timed out', attempt: 1),
          isFalse,
          reason: '$tool must never auto-repeat',
        );
      }
    });

    test('retries file_write, whose content comes from the call', () {
      // Writing the same bytes twice leaves exactly the state one successful
      // write would have.
      expect(
        shouldRetryDeviceCall(
            tool: 'file_write', error: 'resource busy', attempt: 1),
        isTrue,
      );
    });

    test('permanent wins over transient when both words appear', () {
      // "command not found" contains "not found"; "host not found" is a
      // different thing. Permanent is checked first because a wrong retry is
      // the more expensive mistake.
      expect(
        shouldRetryDeviceCall(
          tool: 'file_read',
          error: 'sh: 1: command not found (socket)',
          attempt: 1,
        ),
        isFalse,
      );
    });

    test('an unrecognised failure is left to the model', () {
      // A wrong "no" costs one model turn. A wrong "yes" repeats something
      // that should not have been repeated.
      expect(
        shouldRetryDeviceCall(
            tool: 'net_scan', error: 'something odd happened', attempt: 1),
        isFalse,
      );
    });

    test('gives up after the cap', () {
      expect(
        shouldRetryDeviceCall(
            tool: 'net_scan', error: 'timed out', attempt: kMaxDeviceAttempts),
        isFalse,
      );
      expect(
        shouldRetryDeviceCall(
            tool: 'net_scan',
            error: 'timed out',
            attempt: kMaxDeviceAttempts - 1),
        isTrue,
      );
    });

    test('does not retry a cancellation', () {
      // The user asked for it to stop. Starting it again would be the
      // opposite of what they said.
      expect(
        shouldRetryDeviceCall(
            tool: 'net_scan', error: 'Cancelled', attempt: 1),
        isFalse,
      );
    });

    test('does not retry a scope refusal', () {
      expect(
        shouldRetryDeviceCall(
          tool: 'net_scan',
          error: 'Target is outside the authorized scope',
          attempt: 1,
        ),
        isFalse,
      );
    });

    test('no error text means nothing to judge on', () {
      expect(
        shouldRetryDeviceCall(tool: 'net_scan', error: null, attempt: 1),
        isFalse,
      );
      expect(
        shouldRetryDeviceCall(tool: 'net_scan', error: '', attempt: 1),
        isFalse,
      );
    });
  });

  group('deviceRetryBackoff', () {
    test('short, because a run is paused and someone is watching', () {
      expect(deviceRetryBackoff(1), const Duration(milliseconds: 400));
      expect(deviceRetryBackoff(2), const Duration(milliseconds: 1200));
    });

    test('the whole budget stays under two seconds', () {
      final total = deviceRetryBackoff(1) + deviceRetryBackoff(2);
      expect(total.inMilliseconds, lessThan(2000));
    });
  });
}
