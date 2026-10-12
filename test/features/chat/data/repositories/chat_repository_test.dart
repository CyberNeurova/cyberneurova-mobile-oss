import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';

// One bad row must not lock the user out of the whole conversation.
//
// `getChatWithMessages` is what opens a chat. It dropped rows that were not
// maps, but a row that WAS a map with one wrong-typed field went straight into
// the generated `fromJson` and threw. Nothing above it catches a TypeError, so
// the chat screen showed a generic error, and Retry re-ran the same parse on
// the same payload and threw again — the history was unreachable for good, and
// with no loaded state there was nothing to send a new message into either.
//
// The content-block array below is the shape `/agent/run` already streams for
// assistant turns, so it is the likeliest way for a persisted row to drift.
class _MockApiClient extends Mock implements ApiClient {}

void main() {
  late _MockApiClient client;
  late ChatRepository repo;

  void serve(Map<String, dynamic> body) {
    when(() => client.get<Map<String, dynamic>>(any())).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: ApiConstants.chatById('c1')),
        statusCode: 200,
        data: body,
      ),
    );
  }

  Map<String, dynamic> goodMessage() => {
        'id': 'm1',
        'role': 'user',
        'content': 'hi',
        'createdAt': '2026-09-30T10:00:00Z',
      };

  setUp(() {
    client = _MockApiClient();
    repo = ChatRepository(client);
  });

  group('ChatRepository.getChatWithMessages', () {
    test('skips a malformed message and still opens the conversation',
        () async {
      serve({
        'chat': {'id': 'c1', 'title': 'x'},
        'messages': [
          goodMessage(),
          {
            'id': 'm2',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Hello'},
            ],
            'createdAt': '2026-09-30T10:00:02Z',
          },
        ],
      });

      final loaded = await repo.getChatWithMessages('c1');

      expect(loaded.chat.id, 'c1');
      expect(loaded.chat.title, 'x');
      expect(loaded.messages.map((m) => m.id), ['m1'],
          reason: 'the well-formed message survives its malformed neighbour');
      expect(loaded.messages.single.content, 'hi');
    });

    test('a malformed chat object keeps its id and its well-typed fields',
        () async {
      serve({
        'chat': {
          'id': 'c1',
          'title': 'x',
          'visibility': 'public',
          'isOwner': false,
          'messageCount': '3',
        },
        'messages': [goodMessage()],
      });

      final loaded = await repo.getChatWithMessages('c1');

      expect(loaded.chat.id, 'c1',
          reason: 'the screen still needs an id to send into');
      expect(loaded.chat.title, 'x');
      expect(loaded.chat.visibility, 'public',
          reason: 'a public chat must not read as private in the share sheet');
      expect(loaded.chat.isOwner, isFalse);
      expect(loaded.messages.map((m) => m.id), ['m1'],
          reason: 'a bad chat header must not cost the user the history');
    });

    test('reads history the same way as the paged messages path', () async {
      // Both now go through MessageModel.listFromJson, so metadata.modelName
      // is lifted here too.
      serve({
        'chat': {'id': 'c1'},
        'messages': [
          {
            ...goodMessage(),
            'role': 'assistant',
            'metadata': {'modelName': 'neurova-pro'},
          },
        ],
      });

      final loaded = await repo.getChatWithMessages('c1');

      expect(loaded.messages.single.modelName, 'neurova-pro');
    });

    test('a non-string metadata.modelName does not cost the row', () async {
      // Lifting it unchecked would hand the generated String? cast a number.
      serve({
        'chat': {'id': 'c1'},
        'messages': [
          {
            ...goodMessage(),
            'metadata': {'modelName': 42},
          },
        ],
      });

      final loaded = await repo.getChatWithMessages('c1');

      expect(loaded.messages.map((m) => m.id), ['m1']);
      expect(loaded.messages.single.modelName, isNull);
    });

    test('when every message is malformed the error still surfaces', () async {
      // One bad row is drift in that row; all of them bad is a format change,
      // and opening the chat as if it had no history would be worse than the
      // error screen.
      serve({
        'chat': {'id': 'c1'},
        'messages': [
          {...goodMessage(), 'createdAt': 1727690400000},
          {...goodMessage(), 'id': 'm2', 'createdAt': 1727690400001},
        ],
      });

      await expectLater(repo.getChatWithMessages('c1'), throwsA(anything));
    });
  });
}
