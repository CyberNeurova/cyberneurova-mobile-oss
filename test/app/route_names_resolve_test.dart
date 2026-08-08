import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_search_routing.dart';

/// Every route name the app navigates to must exist in the router.
///
/// go_router resolves names at call time, so a typo is not a compile error —
/// it throws when the user taps. Nothing surfaces it earlier: the analyser
/// sees a valid string, and the screens most likely to hold a stale name are
/// the ones hardest to reach by hand.
///
/// `popOr` is the reason this checks more than one shape. It takes the
/// fallback route name as an ORDINARY PARAMETER:
///
/// ```dart
/// onPressed: () => context.popOr('shell'),
/// ```
///
/// so a `goNamed\('...'\)` grep walks straight past all three of its call
/// sites — and those are the worst ones to get wrong, because `popOr` only
/// reaches its fallback when the navigator stack is empty. That happens on a
/// deep link or after a chain of `pushReplacement` (which the Console does
/// every time you switch shells), which is precisely the path manual testing
/// does not take. A guard is only as good as the shapes it knows about.
void main() {
  final routesFile = File('lib/app/routes.dart');

  final declared = <String>{
    for (final m in RegExp(r"name:\s*'([a-z0-9-]+)'")
        .allMatches(routesFile.readAsStringSync()))
      m.group(1)!,
  };

  /// Both shapes: the go_router calls that take a name literal, and `popOr`,
  /// whose argument is a route name in every position but the syntax.
  final navigationCall = RegExp(
    r'(?:goNamed|pushNamed|pushReplacementNamed|namedLocation|popOr)'
    r"\(\s*'([a-z0-9-]+)'",
  );

  test('the router declares the names this test expects to find', () {
    // If routes.dart is ever restructured so the regex stops matching, every
    // other assertion here silently passes against an empty set.
    expect(declared, contains('chats'));
    expect(declared, contains('chat-detail'));
    expect(declared, contains('shell-session'));
    expect(declared.length, greaterThan(20), reason: '$declared');
  });

  test('the detector catches both call shapes', () {
    String? nameIn(String src) => navigationCall.firstMatch(src)?.group(1);

    expect(nameIn("context.goNamed('chats');"), 'chats');
    expect(nameIn("context.pushNamed('chat-detail', pathParameters: …)"),
        'chat-detail');
    // The shape a plain goNamed grep misses.
    expect(nameIn("onPressed: () => context.popOr('shell'),"), 'shell');
    // And a name that does not exist would be reported, not skipped.
    expect(declared, isNot(contains('definitely-not-a-route')));
  });

  test('every route name used in lib/ is declared in the router', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('routes.dart')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in navigationCall.allMatches(lines[i])) {
          final name = m.group(1)!;
          if (!declared.contains(name)) {
            offenders.add('${file.path}:${i + 1}  $name');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These route names are navigated to but never declared in '
          'lib/app/routes.dart, so tapping throws at runtime:\n'
          '${offenders.join('\n')}',
    );
  });

  test('routeNameForChat only ever returns a real route', () {
    // This one computes the name instead of writing it down, so the check
    // above cannot see it. Search sends every result through here — a stale
    // name would break opening a chat from search and nothing else, which is
    // a thin enough path to go unnoticed.
    for (final section in [
      AppConstants.sectionShell,
      AppConstants.sectionResearch,
      AppConstants.sectionCode,
      AppConstants.sectionChat,
    ]) {
      final name = routeNameForChat(
        ChatModel(id: 'x', title: 'x', section: section),
      );
      expect(declared, contains(name), reason: 'section $section -> $name');
    }
  });
}
