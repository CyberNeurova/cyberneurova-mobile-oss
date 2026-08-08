import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A raw Dart exception must never reach the screen.
///
/// Found in FIVE places on 2026-08-05, all user-facing: the chat stream
/// (`TimeoutException after 0:05:00.000000: No stream event` in a failure
/// bubble), image generation ("fetch failed"), voice transcription, attachment
/// uploads (a stack trace truncated to 120 characters), and three shell
/// SnackBars built as `"Couldn't do X: $e"`.
///
/// Every one was written by someone reaching for the quickest way to say
/// something went wrong. A grep-in-a-test is blunt, but the alternative is
/// finding the sixth in production, and the fix is always the same call:
/// `userMessageFor(context, e)`.
void main() {
  /// `$e` as a whole interpolation, not `$eventName`.
  final bareExceptionInterpolation = RegExp(r'\$e\b');
  final exceptionIntoState = RegExp(r'=\s*e\.toString\(\)\s*;');

  // Prove the detector works before trusting it. A guard that has quietly
  // stopped matching is worse than no guard: it reports success forever.
  test('the detector catches the lines that shipped', () {
    for (final shipped in [
      r'content: Text("Could not start a code session: $e"),',
      r"SnackBar(content: Text('Could not delete chat: $e')),",
    ]) {
      expect(
        shipped.contains('Text(') &&
            bareExceptionInterpolation.hasMatch(shipped),
        isTrue,
        reason: shipped,
      );
    }
    expect(
      exceptionIntoState.hasMatch('      streamError = e.toString();'),
      isTrue,
    );
    // And leaves the correct form alone.
    expect(
      exceptionIntoState
          .hasMatch('      streamError = humanStreamError(e);'),
      isFalse,
    );
    // `$eventName` is not an exception.
    expect(
      bareExceptionInterpolation.hasMatch(r"Text('tapped $eventName')"),
      isFalse,
    );
  });

  test('no presentation code renders an exception directly', () {
    final offenders = <String>[];

    for (final dir in ['lib/features', 'lib/shared']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;

      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i].trim();

          // Comments describe these bugs on purpose — see billing_labels.dart,
          // where the wrong idiom is quoted in the note explaining it.
          if (l.startsWith('//')) continue;
          // Logging an exception is correct: that goes to logcat, not a user.
          if (l.contains('debugPrint(') || l.contains('developer.log(')) {
            continue;
          }
          // ONE deliberate exception, and it earns it. The sign-in failure
          // dialog shows the full error with a Copy button on purpose: a
          // snackbar truncated the server's message and made recurring
          // "access denied" bugs impossible to pin down. That is a diagnostic
          // the user is being asked to paste back, not an error message
          // dressed up as one. The rule is "never show a raw exception AS the
          // explanation", not "never show one at all".
          if (file.path.endsWith('social_sign_in_button.dart')) continue;

          // Not just `Text($e)`. The drawer passed `message: '$e'` to a widget
          // that renders it, which the Text-only check walked straight past —
          // the fourteenth instance of this bug, found by reading the file
          // rather than by the guard meant to find it.
          //
          // So: any `$e` inside presentation code that is not logging. There
          // is no legitimate reason to interpolate an exception into a string
          // here except to show it to someone.
          final rendersInWidget = bareExceptionInterpolation.hasMatch(l) ||
              (l.contains('Text(') && l.contains('e.toString()'));
          final storesForRender = exceptionIntoState.hasMatch(l);

          if (rendersInWidget || storesForRender) {
            offenders.add('${file.path}:${i + 1}  $l');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Render these through userMessageFor(context, e) instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
