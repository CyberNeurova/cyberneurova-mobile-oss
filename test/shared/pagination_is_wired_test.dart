import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `loadMore` nobody calls is a list that silently stops.
///
/// All three paginated lists — chats, images, research — shipped with a
/// `loadMore()` that was written, commented, guarded against re-entrancy, and
/// called from NOWHERE. The app fetched one page of
/// `AppConstants.defaultPageLimit` (20) and never another, so on the owner's
/// account the drawer showed three conversations while the web showed many
/// more: everything older than the twentieth newest chat was unreachable.
///
/// It is invisible until someone has enough history to notice, it looks
/// exactly like a server problem from the user's side, and the code reads as
/// correct — the pagination is all there. Nothing but "is it called?" catches
/// it, which is what this asks.
void main() {
  final defines = RegExp(r'Future<void>\s+loadMore\s*\(');
  final calls = RegExp(r'\.loadMore\s*\(');

  List<File> dartFiles() => [
        for (final f
            in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.freezed.dart'))
            f,
      ];

  test('the detector tells a definition from a call', () {
    expect(defines.hasMatch('  Future<void> loadMore() async {'), isTrue);
    expect(calls.hasMatch('  Future<void> loadMore() async {'), isFalse);
    expect(calls.hasMatch('ref.read(chatListProvider.notifier).loadMore();'),
        isTrue);
  });

  test('every loadMore has a caller', () {
    final definedIn = <String>[];
    var callSites = 0;

    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      if (defines.hasMatch(src)) definedIn.add(f.path);
      callSites += calls.allMatches(src).length;
    }

    expect(definedIn, isNotEmpty,
        reason: 'the guard is pointless if it stops finding the definitions');

    // One call site per definition, at least. They live in the widgets that
    // scroll — the drawer, the gallery grid, the research list — not beside
    // the notifier, so this counts across the whole of lib/.
    expect(
      callSites,
      greaterThanOrEqualTo(definedIn.length),
      reason: 'loadMore is defined in ${definedIn.length} place(s) but called '
          '$callSites time(s). A list that cannot fetch its second page shows '
          'the first 20 rows forever:\n${definedIn.join('\n')}',
    );
  });
}
