import 'package:cyberneurova_mobile/features/user/data/models/usage_model.dart';

/// The usage figure to put on the Settings row.
///
/// There are two counters. `user.tokens` is the legacy one; v2 accounts fill
/// `weekly` instead and leave the legacy one at zero. The row read
/// `user.tokens` unconditionally, so the owner's Pro account showed
/// **"0K / 60000K"** after a day of heavy use while the Usage screen's own
/// breakdown, one tap away, showed 2.4M of 1400M used.
///
/// A usage row that always says zero is worse than no usage row: it does not
/// merely fail to inform, it tells the user their work is not being counted.
///
/// Prefers the live weekly bucket, falls back to the legacy pair, and shows
/// nothing when neither is available — rather than inventing a zero.
String? usageRowValue({
  required UsageDetail? usage,
  int? legacyUsed,
  int? legacyLimit,
}) {
  final weekly = usage?.weekly;
  if (usage != null && !usage.legacy && weekly != null && weekly.limit > 0) {
    return '${_short(weekly.used)} / ${_short(weekly.limit)}';
  }
  if (legacyUsed != null && legacyLimit != null && legacyLimit > 0) {
    return '${_short(legacyUsed)} / ${_short(legacyLimit)}';
  }
  return null;
}

/// Compact token counts. A row beside a label has no room for "60000K".
String _short(int n) {
  if (n >= 1000000) {
    final m = n / 1000000;
    return '${m >= 10 ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
  }
  if (n >= 1000) {
    final k = n / 1000;
    return '${k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
  }
  return '$n';
}
