import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';

/// How the phone decides an answer was researched rather than recalled.
///
/// It used to infer this from the absence of a `tool_call` frame. That was
/// wrong the moment the pre-search moved server-side: it emits no tool call,
/// so a properly sourced answer was labelled as coming from memory. Verified
/// on prod — the curl answer matched core's own verified-fixed output and the
/// phone still printed "no sources were fetched" underneath it.
///
/// Core now says so directly (reply to outbox 063):
///
/// ```json
/// {"type":"system","subtype":"web_search_results","count":10,
///  "sources":["https://curl.se/docs/releases.html", …]}
/// ```
///
/// emitted ONLY when results actually came back. So `count > 0` is the signal,
/// no frame means recalled or a SearXNG miss — and both of those read the same
/// way to someone deciding whether to trust the answer.
///
/// These cases pin the decision rather than the wiring, because the decision
/// is what shows up under the reply.
bool _shouldWarnUnsourced({
  required int searchedCount,
  required bool anyToolCall,
  required bool isResearch,
  required bool hasText,
  required bool errored,
}) =>
    searchedCount == 0 && !anyToolCall && !errored && hasText && isResearch;

void main() {
  group('the note fires only when nothing was fetched', () {
    test('a server-side pre-search silences it', () {
      // The exact case that was wrong: sources fetched, zero tool calls.
      expect(
        _shouldWarnUnsourced(
            searchedCount: 10,
            anyToolCall: false,
            isResearch: true,
            hasText: true,
            errored: false),
        isFalse,
      );
    });

    test('no frame at all still warns', () {
      expect(
        _shouldWarnUnsourced(
            searchedCount: 0,
            anyToolCall: false,
            isResearch: true,
            hasText: true,
            errored: false),
        isTrue,
      );
    });

    test('a device tool that fetched counts as sourced', () {
      // A run that went and got a page itself is sourced whatever the
      // pre-search did.
      expect(
        _shouldWarnUnsourced(
            searchedCount: 0,
            anyToolCall: true,
            isResearch: true,
            hasText: true,
            errored: false),
        isFalse,
      );
    });

    test('a search that returned nothing warns, because it did', () {
      // SearXNG miss: core emits no frame, so count stays 0. The answer came
      // from memory and the reader should know.
      expect(
        _shouldWarnUnsourced(
            searchedCount: 0,
            anyToolCall: false,
            isResearch: true,
            hasText: true,
            errored: false),
        isTrue,
      );
    });
  });

  group('and only where it means something', () {
    test('not outside Research', () {
      // Console and Code are not making a claim about sources.
      expect(
        _shouldWarnUnsourced(
            searchedCount: 0,
            anyToolCall: false,
            isResearch: false,
            hasText: true,
            errored: false),
        isFalse,
      );
    });

    test('not on a failed run', () {
      // An error already explains itself; two notes is noise.
      expect(
        _shouldWarnUnsourced(
            searchedCount: 0,
            anyToolCall: false,
            isResearch: true,
            hasText: true,
            errored: true),
        isFalse,
      );
    });

    test('not under an empty reply', () {
      expect(
        _shouldWarnUnsourced(
            searchedCount: 0,
            anyToolCall: false,
            isResearch: true,
            hasText: false,
            errored: false),
        isFalse,
      );
    });
  });

  group('per-surface turn budgets (outbox 054)', () {
    test('every surface stays inside the server clamp', () {
      for (final s in AgentSurface.values) {
        expect(s.maxTurns, greaterThan(0), reason: s.title);
        expect(s.maxTurns, lessThanOrEqualTo(50),
            reason: '${s.title} — core clamps at 50');
      }
    });

    test('Code gets the most, Console the fewest', () {
      // Code was the surface hitting the ceiling mid-build; Console is watched
      // by someone who can steer after any answer.
      expect(AgentSurface.code.maxTurns,
          greaterThan(AgentSurface.research.maxTurns));
      expect(AgentSurface.research.maxTurns,
          greaterThan(AgentSurface.console.maxTurns));
    });
  });
}
