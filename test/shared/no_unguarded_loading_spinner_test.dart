import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A spinner branch must be guarded by the value, not by the flag alone.
///
/// `AsyncValue.isLoading` is true on the FIRST load and on every refresh
/// afterwards, while `valueOrNull` is null on the first load and on FAILURE.
/// So a screen that renders cached data has exactly one correct shape:
///
/// ```dart
/// child: async.isLoading && async.valueOrNull == null
///     ? spinner
///     : async.hasError && async.valueOrNull == null
///         ? error
///         : list
/// ```
///
/// Getting it wrong fails in two directions at once, which is why it kept
/// coming back. Found on 2026-08-05 in the Code session list, Archived chats
/// and chat Search:
///
///   * Bare `isLoading` in front: the list the user is already reading blanks
///     to a spinner on every background refresh, and — because the branch
///     swallows everything below it — the error case underneath becomes dead
///     code that can never render. The Code screen had a correctly written
///     error ladder that had been unreachable since the day it was added.
///   * No `hasError` branch at all: a failed load falls through to the empty
///     state, so a broken request says "No archived chats" or "No chats match".
///     Telling someone their data is gone when the request merely failed is the
///     worst available lie.
///
/// The Shell session list had it right (`chats == null && chatsAsync.isLoading`)
/// and is what the others now look like.
void main() {
  /// A ternary condition that ends at `.isLoading` — the spinner-branch shape.
  /// `if (x.isLoading)` and `final b = x.isLoading;` end in `)` and `;`, so
  /// they do not match: this is aimed at the condition of a widget ternary.
  final bareLoadingCondition = RegExp(r'\.isLoading\s*$');

  bool isUnguarded(String line) {
    final l = line.trim();
    if (!bareLoadingCondition.hasMatch(l)) return false;
    // Combined with a value check — `chats == null && chatsAsync.isLoading` —
    // is the correct form and the whole point of the guard.
    return !l.contains('&&') && !l.contains('||');
  }

  // A guard that cannot fail reports success forever. Prove it catches the
  // three lines that shipped before trusting it to police the repo.
  test('the detector catches the lines that shipped', () {
    for (final shipped in [
      '            child: chatsAsync.isLoading',
      '              child: chatsAsync.isLoading',
    ]) {
      expect(isUnguarded(shipped), isTrue, reason: shipped);
    }

    // The correct forms are left alone.
    expect(
      isUnguarded('      body: chats == null && chatsAsync.isLoading'),
      isFalse,
    );
    expect(
      isUnguarded(
          'child: chatsAsync.isLoading && chatsAsync.valueOrNull == null'),
      isFalse,
    );
    // Not every mention of the flag is a spinner branch.
    expect(isUnguarded('    if (authState.isLoading) return;'), isFalse);
    expect(isUnguarded('    final busy = ref.watch(p).isLoading;'), isFalse);
  });

  test('no screen that renders cached data blanks it on refresh', () {
    final offenders = <String>[];

    for (final dir in ['lib/features', 'lib/shared']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;

      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;

        final lines = file.readAsLinesSync();

        // Only files that render a cached value can blank it. A one-shot
        // fetch with nothing to preserve is entitled to a plain spinner.
        final rendersCachedValue = lines.any((l) => l.contains('valueOrNull'));
        if (!rendersCachedValue) continue;

        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (isUnguarded(lines[i])) {
            offenders.add('${file.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Guard the spinner on the value, not the flag — otherwise a '
          'refresh blanks the list and the error branch below is dead:\n'
          '${offenders.join('\n')}',
    );
  });
}
