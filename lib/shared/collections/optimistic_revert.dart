/// Undoing ONE optimistic change without undoing everything else.
///
/// The pattern these lists all use is: remove the row on screen immediately,
/// send the request, put the row back if it fails. The "put it back" step kept
/// being written as `state = AsyncData(listCapturedBeforeTheRequest)`, which
/// restores far more than the one row — it restores the whole list as it was
/// before, discarding every other change made while the request was in flight.
///
/// Those other changes are not hypothetical. Each row is its own request, and
/// the screens let you act on several in a row without waiting, so a failure
/// arriving late would resurrect rows the server had already deleted. The user
/// sees them come back, refreshes, and they are gone again — the UI disagreeing
/// with the server about work that actually succeeded.
///
/// Reverting means putting the affected row back into the list AS IT STANDS
/// NOW, not replacing the list.
library;

/// Re-insert [item] into [list] at [index], clamped into range.
///
/// [index] is where the row was before it was optimistically removed. It is a
/// best-effort position: the list may have changed length in the meantime, and
/// putting the row back roughly where the user last saw it beats appending it
/// to the end, which reads as a different row appearing.
List<T> restoreAt<T>(List<T> list, T item, int index) {
  final at = index.clamp(0, list.length);
  return [...list.sublist(0, at), item, ...list.sublist(at)];
}

/// Index of the first element satisfying [test], or `-1`.
///
/// `indexWhere` already does this; it is named here so call sites read as
/// "remember where this row was" rather than as a search.
int positionOf<T>(List<T> list, bool Function(T) test) => list.indexWhere(test);
