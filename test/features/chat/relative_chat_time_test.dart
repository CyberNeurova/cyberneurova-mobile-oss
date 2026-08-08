import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_list_row.dart';

/// The timestamp under every row in the drawer, search and archived lists.
///
/// It is the only thing distinguishing two chats with similar titles, so its
/// boundaries are worth pinning: they are all off-by-one candidates, and a
/// wrong one is the sort of thing nobody reports because it just looks a bit
/// odd rather than broken.
///
/// This is deliberately NOT the same formatter as `recordTime` in
/// `shared/time/record_time.dart`, and the two disagree on purpose — see the
/// future-timestamp case at the bottom.
void main() {
  String at(Duration ago) => relativeChatTime(DateTime.now().subtract(ago));

  group('the near boundaries', () {
    test('under a minute reads as now', () {
      expect(at(const Duration(seconds: 0)), 'Just now');
      expect(at(const Duration(seconds: 59)), 'Just now');
    });

    test('minutes, up to the hour', () {
      expect(at(const Duration(minutes: 1)), '1m ago');
      expect(at(const Duration(minutes: 59)), '59m ago');
    });

    test('hours, up to the day', () {
      expect(at(const Duration(minutes: 60)), '1h ago');
      expect(at(const Duration(hours: 23)), '23h ago');
    });
  });

  group('the day boundaries', () {
    test('exactly a day ago is Yesterday, not 1d ago', () {
      expect(at(const Duration(hours: 24)), 'Yesterday');
      expect(at(const Duration(hours: 47)), 'Yesterday');
    });

    test('two to six days count in days', () {
      expect(at(const Duration(hours: 48)), '2d ago');
      expect(at(const Duration(days: 6, hours: 23)), '6d ago');
    });

    test('a week or more falls back to a date', () {
      // The relative form stops being useful around here — "9d ago" makes the
      // reader do arithmetic that a date does for them.
      expect(at(const Duration(days: 7)), matches(r'^\d{1,2} [A-Z][a-z]{2}$'));
      expect(at(const Duration(days: 40)), matches(r'^\d{1,2} [A-Z][a-z]{2}$'));
    });

    test('the date form names the right day and month', () {
      // Anchored well in the past, because anything inside a week takes a
      // relative branch instead — my first attempt at this test used today's
      // date and a future one, and got "23h ago" and "Just now".
      final old = DateTime.now().subtract(const Duration(days: 200));
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      expect(relativeChatTime(old), '${old.day} ${months[old.month - 1]}');
    });

    test('the date is day-first, never month-first', () {
      // The same rule the sessions screen was fixed to follow: a month-first
      // date is read wrong everywhere outside the United States. Day 13+
      // makes the ordering unambiguous to assert.
      var d = DateTime.now().subtract(const Duration(days: 200));
      while (d.day < 13) {
        d = d.subtract(const Duration(days: 1));
      }
      expect(relativeChatTime(d), startsWith('${d.day} '));
    });

    test('the date form carries no year, so it is only for recent chats', () {
      // Recorded rather than asserted as ideal: two chats a year apart on the
      // same date read identically. Fine for a list sorted by recency,
      // ambiguous the moment it is not.
      final a = DateTime.now().subtract(const Duration(days: 200));
      final b = DateTime(a.year - 1, a.month, a.day);
      expect(relativeChatTime(a), relativeChatTime(b));
    });
  });

  test('a missing timestamp renders as nothing at all', () {
    // The row has no space for "unknown"; an empty subtitle is the design.
    expect(relativeChatTime(null), '');
  });

  test('a future timestamp reads as now, unlike recordTime', () {
    // Phone and server clocks drift, so a stamp a few seconds ahead is normal.
    // Here that rounds to "Just now", which is honest enough for a chat list.
    //
    // `recordTime` deliberately does the opposite and falls back to a date,
    // because it labels Active sessions — and telling someone a session was
    // used "just now" when the stamp is tomorrow would hide exactly the thing
    // that screen exists to show. Same input, different answer, on purpose.
    expect(relativeChatTime(DateTime.now().add(const Duration(minutes: 5))),
        'Just now');
  });
}
