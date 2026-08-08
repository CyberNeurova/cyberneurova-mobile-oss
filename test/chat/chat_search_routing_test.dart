import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_search_routing.dart';

ChatModel _chat({
  String title = 'Something',
  String section = AppConstants.sectionChat,
  int messageCount = 2,
}) =>
    ChatModel(
        id: 'x', title: title, section: section, messageCount: messageCount);

void main() {
  group('isSearchable', () {
    test('an agent session is findable despite messageCount 0', () {
      // The bug: agent turns are never written server-side, so every Console
      // and Research session reports 0 messages and was filtered out.
      for (final section in [
        AppConstants.sectionShell,
        AppConstants.sectionResearch,
        AppConstants.sectionCode,
      ]) {
        expect(
          isSearchable(_chat(
              title: 'Run the shell command sleep 30',
              section: section,
              messageCount: 0)),
          isTrue,
          reason: section,
        );
      }
    });

    test('a blank chat is still noise', () {
      // The guard this replaces was there for a reason — keep that reason.
      expect(
        isSearchable(_chat(title: 'New Chat', messageCount: 0)),
        isFalse,
      );
      expect(isSearchable(_chat(title: '', messageCount: 0)), isFalse);
      expect(isSearchable(_chat(title: '??', messageCount: 0)), isFalse);
    });

    test('a plain chat with messages is findable even if badly named', () {
      expect(isSearchable(_chat(title: 'New Chat', messageCount: 4)), isTrue);
    });
  });

  group('routeNameForChat', () {
    test('a Console session opens the terminal screen', () {
      expect(routeNameForChat(_chat(section: AppConstants.sectionShell)),
          'shell-session');
    });

    test('everything else opens the chat screen', () {
      for (final section in [
        AppConstants.sectionChat,
        AppConstants.sectionResearch,
        AppConstants.sectionCode,
      ]) {
        expect(routeNameForChat(_chat(section: section)), 'chat-detail',
            reason: section);
      }
    });
  });

  group('searchSurfaceLabel', () {
    test('names the surface so two identical rows are not ambiguous', () {
      expect(searchSurfaceLabel(_chat(section: AppConstants.sectionShell)),
          'Console');
      expect(searchSurfaceLabel(_chat(section: AppConstants.sectionResearch)),
          'Research');
      expect(searchSurfaceLabel(_chat(section: AppConstants.sectionCode)),
          'Code');
    });

    test('a plain chat needs no label', () {
      expect(searchSurfaceLabel(_chat(section: AppConstants.sectionChat)),
          isNull);
    });
  });
}
