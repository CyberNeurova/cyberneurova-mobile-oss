import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dates must not be month-first.
///
/// The Active sessions screen rendered `7/27/2026` on an en-GB device — the one
/// screen where a date is the difference between "that was me last week" and
/// "that was not me". Every other absolute date in the app was already ISO;
/// that screen had quietly grown its own formatter.
///
/// `M/D/YYYY` is ambiguous everywhere outside the United States and is read
/// wrong in most of the world, so it is not a style preference. Use
/// `isoDate` / `recordTime` from `shared/time/record_time.dart`.
///
/// `.` is used rather than `[^\n]` on purpose: Dart's dot already excludes
/// newlines, and every attempt to write the escape through tooling turned it
/// into a literal line break.
final _monthFirst = RegExp(r'\.month\}?.{0,12}/.{0,12}\.day');

void main() {
  // A guard that cannot fail is worthless, so prove it catches the real one
  // before trusting it to police the repo.
  test('the detector catches the line that shipped', () {
    // Verbatim from sessions_screen.dart before the fix.
    expect(
      _monthFirst.hasMatch(r"return '${dt.month}/${dt.day}/${dt.year}';"),
      isTrue,
    );
    // And does not fire on the ISO form that replaced it.
    expect(
      _monthFirst.hasMatch(
          r"return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';"),
      isFalse,
    );
  });

  test('no month-first date formatting in lib/', () {
    final offenders = <String>[];

    final root = Directory('lib');
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      // Generated localisations carry their own date patterns.
      if (file.path.contains('l10n')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trim();
        if (l.startsWith('//')) continue;
        if (_monthFirst.hasMatch(l)) {
          offenders.add('${file.path}:${i + 1}  $l');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Month-first dates are misread outside the US. Use isoDate():\n'
          '${offenders.join('\n')}',
    );
  });
}
