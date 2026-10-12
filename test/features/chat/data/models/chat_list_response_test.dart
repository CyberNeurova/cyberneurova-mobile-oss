import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';

/// GET /chat is fetched once per section and the four pages are awaited
/// together, so a row this parser cannot read used to cost the user every
/// section, not one row: no list at all on a fresh login, and a list frozen
/// on the disk cache otherwise. Each drift below is one the generated parser
/// threw a TypeError on.
void main() {
  group('ChatListResponse.fromJson skips rows it cannot read', () {
    const good = {'id': 'a1', 'title': 'ok'};
    const alsoGood = {'id': 'c3', 'title': 'still here'};

    final drifts = <String, Object?>{
      // What node-postgres hands back for a raw COUNT(*): a bigint string.
      'messageCount as a string': {
        'id': 'b2',
        'title': 'ls',
        'section': 'shell',
        'messageCount': '12',
      },
      'lastMessage as an object': {
        'id': 'b2',
        'lastMessage': {'role': 'assistant', 'content': 'hi'},
      },
      'updatedAt as epoch millis': {'id': 'b2', 'updatedAt': 1727690400000},
      'isOwner as 1': {'id': 'b2', 'isOwner': 1},
      'a null entry': null,
      'a non-object entry': 'b2',
    };

    for (final MapEntry(key: name, value: bad) in drifts.entries) {
      test('$name: the bad row is dropped, its neighbours are kept', () {
        final resp = ChatListResponse.fromJson({
          'chats': [good, bad, alsoGood],
          'nextCursor': 'cur-1',
          'hasMore': true,
        });
        expect(resp.chats.map((c) => c.id), ['a1', 'c3']);
        // The page metadata does not depend on the rows parsing.
        expect(resp.nextCursor, 'cur-1');
        expect(resp.hasMore, isTrue);
      });
    }

    test('a well-formed page parses exactly as before', () {
      final resp = ChatListResponse.fromJson({
        'chats': [
          {
            'id': 'a1',
            'title': 'Trip plan',
            'visibility': 'public',
            'section': 'research',
            'isPublishedToDiscover': true,
            'isOwner': false,
            'createdAt': '2026-09-30T10:00:00.000Z',
            'updatedAt': '2026-09-30T11:30:00.000Z',
            // A whole-number double is a valid num and always parsed.
            'messageCount': 12.0,
            'lastMessage': 'see you there',
          },
          {'id': 'b2'},
        ],
        'nextCursor': 'b2',
        'hasMore': true,
      });
      expect(
        resp,
        ChatListResponse(
          chats: [
            ChatModel(
              id: 'a1',
              title: 'Trip plan',
              visibility: 'public',
              section: 'research',
              isPublishedToDiscover: true,
              isOwner: false,
              createdAt: DateTime.utc(2026, 9, 30, 10),
              updatedAt: DateTime.utc(2026, 9, 30, 11, 30),
              messageCount: 12,
              lastMessage: 'see you there',
            ),
            const ChatModel(id: 'b2'),
          ],
          nextCursor: 'b2',
          hasMore: true,
        ),
      );
    });

    test('missing or wrong-typed page fields fall back, never throw', () {
      expect(ChatListResponse.fromJson({}), const ChatListResponse());
      final resp = ChatListResponse.fromJson({
        'chats': {'id': 'a1'},
        'nextCursor': 42,
        'hasMore': 'true',
      });
      expect(resp.chats, isEmpty);
      expect(resp.nextCursor, isNull);
      // `hasMore` without a usable answer means stop paging, as when absent.
      expect(resp.hasMore, isFalse);
    });

    test('a page where every row is unreadable fails rather than reads empty',
        () {
      // One bad row is drift in that row; all of them bad is the format
      // changing, and an empty page would be taken for "no chats".
      expect(
        () => ChatListResponse.fromJson({
          'chats': [
            {'id': 'a1', 'messageCount': '12'},
            {'id': 'b2', 'messageCount': '7'},
          ],
        }),
        throwsA(anything),
      );
      // An empty page is still just empty.
      expect(ChatListResponse.fromJson({'chats': []}).chats, isEmpty);
    });
  });
}
