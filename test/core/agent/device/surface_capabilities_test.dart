import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';

void main() {
  test('every section that gets device tools maps to a surface', () {
    // If a surface is added to the device-tool gate without a description
    // here, the model gets tools and no idea what they are for — which is the
    // exact state this was written to end.
    expect(AgentSurface.forSection(AppConstants.sectionShell),
        AgentSurface.console);
    expect(AgentSurface.forSection(AppConstants.sectionCode), AgentSurface.code);
    expect(AgentSurface.forSection(AppConstants.sectionResearch),
        AgentSurface.research);
  });

  test('a plain chat has no surface', () {
    // Null is what the rest of the app reads as "this session cannot act on
    // the device", so it must not quietly become a default surface.
    expect(AgentSurface.forSection(AppConstants.sectionChat), isNull);
    expect(AgentSurface.forSection(null), isNull);
    expect(AgentSurface.forSection('something-the-server-added-later'), isNull);
  });

  test('each surface says what it is for, and says it differently', () {
    final focuses = {for (final s in AgentSurface.values) s.focus};
    expect(focuses.length, AgentSurface.values.length,
        reason: 'identical guidance would leave the surfaces interchangeable');

    for (final s in AgentSurface.values) {
      expect(s.promptBlock, startsWith('SURFACE: ${s.title}'));
      expect(s.userCapabilities, isNotEmpty);
      expect(s.summary.trim(), isNotEmpty);
    }
  });

  group('capability claims match what is implemented', () {
    test('Code does not promise unlimited context', () {
      // `_withPriorTurns` carries SIX turns, truncated to 600 characters each,
      // with tool results excluded — and agent turns are not stored
      // server-side at all. "The whole project as context" was a
      // promise nothing in the app keeps, on the screen a user reads before
      // deciding to build something on their phone.
      const code = AgentSurface.code;
      final text =
          '${code.summary} ${code.userCapabilities.join(' ')}'.toLowerCase();
      expect(text, isNot(contains('whole project as context')));
      expect(text, isNot(contains('keeps the whole project in view')));
      // What is actually true: the files persist and can be re-read.
      expect(text, contains('re-read'));
    });

    test('no surface claims a capability with no tool behind it', () {
      // The Agent environment screen promised the agent could install and
      // remove apps and list packages once wireless debugging was paired;
      // `PrivilegedShell` has no callers, and there is no uninstall or
      // package-list tool. Keep that wording out of the surface copy too.
      for (final s in AgentSurface.values) {
        final text =
            '${s.summary} ${s.userCapabilities.join(' ')}'.toLowerCase();
        expect(text, isNot(contains('uninstall')), reason: s.title);
        expect(text, isNot(contains('package list')), reason: s.title);
        expect(text, isNot(contains('without a prompt')), reason: s.title);
      }
    });
  });
}
