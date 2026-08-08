/// How old a *record* is.
///
/// The app has two registers for time, and they are not an accident:
///
/// * `relativeChatTime` (chat_list_row.dart) is conversational — "Just now",
///   "Yesterday", "12 Mar". Right for a list of conversations, where the
///   month and day is enough and a year would be noise.
/// * This one is precise. Recent times are still relative, because "3d ago"
///   is what a person actually wants, but anything older resolves to an
///   unambiguous ISO date. It is used where reading a date wrong has a
///   consequence: active sessions, saved memories, research sessions.
///
/// They were three identical private copies before this, and they had already
/// drifted — the sessions screen rendered `M/D/YYYY`, US-only, on an en-GB
/// device, on the screen where a date is the difference between "that was me
/// last week" and "that was not me".
///
/// Deliberately NOT merged with `relativeChatTime`. One helper for both would
/// either make a security screen fuzzy or make the chat list clinical.
library;

/// `just now` · `5m ago` · `3h ago` · `2d ago` · `2026-07-27`.
///
/// [ifNull] is what to say when there is no timestamp at all — "recently" for
/// a list row that must say something, empty for a caller that would rather
/// print nothing.
String recordTime(DateTime? dt, {String ifNull = ''}) {
  if (dt == null) return ifNull;
  final local = dt.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.isNegative) return isoDate(local);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return isoDate(local);
}

/// `2026-07-27`. Unambiguous in every locale, which `M/D/YYYY` is not.
String isoDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
    '-${dt.day.toString().padLeft(2, '0')}';
