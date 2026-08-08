import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';

// Sahachiel: StreamEvent.fromJson parses every line of the /complete NDJSON
// stream. It had blanket `as String?` casts that throw on a wrong-typed field -
// and the backend confirmed `code` sometimes arrives as a number - which would
// kill the parse of the event. These lock the type-safe behaviour (and the
// unknown-type -> error fallback), plus the basic chat/message parsing.
void main() {
  group('StreamEvent.fromJson', () {
    test('start carries messageId / model / mode', () {
      final e = StreamEvent.fromJson({
        'type': 'start',
        'messageId': 'm1',
        'model': 'neurova-pro',
        'mode': 'resume',
      });
      expect(e, isA<StreamEventStart>());
      e as StreamEventStart;
      expect(e.messageId, 'm1');
      expect(e.model, 'neurova-pro');
      expect(e.mode, 'resume');
    });

    test('start with no messageId falls back to empty, never throws', () {
      final e = StreamEvent.fromJson({'type': 'start'});
      expect(e, isA<StreamEventStart>());
      expect((e as StreamEventStart).messageId, '');
    });

    test('token carries content; a non-string content degrades to empty', () {
      expect(
        (StreamEvent.fromJson({'type': 'token', 'content': 'hi'})
                as StreamEventToken)
            .content,
        'hi',
      );
      expect(
        (StreamEvent.fromJson({'type': 'token', 'content': 123})
                as StreamEventToken)
            .content,
        '',
      );
    });

    test('usage reads the nested counts, defaulting a missing block to 0', () {
      final e = StreamEvent.fromJson({
        'type': 'usage',
        'usage': {'inputTokens': 10, 'outputTokens': 20, 'totalTokens': 30},
      }) as StreamEventUsage;
      expect(e.inputTokens, 10);
      expect(e.outputTokens, 20);
      expect(e.totalTokens, 30);

      final missing = StreamEvent.fromJson({'type': 'usage'}) as StreamEventUsage;
      expect(missing.totalTokens, 0);
    });

    test('done carries finishReason / truncated; bad truncated -> false', () {
      final e = StreamEvent.fromJson({
        'type': 'done',
        'messageId': 'm1',
        'finishReason': 'length',
        'truncated': true,
        'mode': 'resume',
      }) as StreamEventDone;
      expect(e.messageId, 'm1');
      expect(e.finishReason, 'length');
      expect(e.truncated, isTrue);
      expect(e.mode, 'resume');

      final weird = StreamEvent.fromJson({'type': 'done', 'truncated': 'yes'})
          as StreamEventDone;
      expect(weird.truncated, isFalse);
    });

    test('status carries the web-search fields', () {
      final e = StreamEvent.fromJson({
        'type': 'status',
        'status': 'web-searched',
        'query': 'flutter pinning',
        'resultCount': 5,
        'source': 'web',
      }) as StreamEventStatus;
      expect(e.status, 'web-searched');
      expect(e.query, 'flutter pinning');
      expect(e.resultCount, 5);
      expect(e.source, 'web');
    });

    test('error uses message, then the error fallback', () {
      expect(
        (StreamEvent.fromJson({'type': 'error', 'message': 'boom'})
                as StreamEventError)
            .message,
        'boom',
      );
      expect(
        (StreamEvent.fromJson({'type': 'error', 'error': 'fallback'})
                as StreamEventError)
            .message,
        'fallback',
      );
    });

    test('a numeric error code does not throw (the backend NDJSON quirk)', () {
      // {"type":"error","code":500} used to throw on `code as String?` and kill
      // the stream-event parse. Now code reads as null and the message survives.
      final e = StreamEvent.fromJson({
        'type': 'error',
        'message': 'rate limited',
        'code': 500,
      });
      expect(e, isA<StreamEventError>());
      e as StreamEventError;
      expect(e.code, isNull);
      expect(e.message, 'rate limited');
    });

    test('an unknown or non-string type degrades to an error event', () {
      expect(
        (StreamEvent.fromJson({'type': 'wat'}) as StreamEventError).message,
        contains('Unknown event type'),
      );
      // type as a number must not throw the switch.
      final numType = StreamEvent.fromJson({'type': 7});
      expect(numType, isA<StreamEventError>());
    });
  });

  group('ChatModel / MessageModel.fromJson', () {
    test('ChatModel parses with sensible defaults', () {
      final c = ChatModel.fromJson({'id': 'c1', 'title': 'Hello'});
      expect(c.id, 'c1');
      expect(c.title, 'Hello');
      expect(c.visibility, 'private');
      expect(c.isOwner, isTrue);
      expect(c.messageCount, 0);
    });

    test('MessageModel parses role / content / attachments', () {
      final m = MessageModel.fromJson({
        'id': 'msg1',
        'chatId': 'c1',
        'role': 'assistant',
        'content': 'hi there',
        'attachments': [
          {'url': 'https://x/y.png', 'contentType': 'image/png'},
        ],
      });
      expect(m.role, 'assistant');
      expect(m.content, 'hi there');
      expect(m.attachments, hasLength(1));
      expect(m.attachments.first.contentType, 'image/png');
      expect(m.isError, isFalse); // client-only default
    });
  });

  group('MessagesResponse.fromJson (real {messages, cursor} contract)', () {
    test('surfaces cursor.before as nextCursor (pagination keeps advancing)',
        () {
      final resp = MessagesResponse.fromJson({
        'messages': [
          {'id': 'msg1', 'role': 'user', 'content': 'hi'},
        ],
        'hasMore': true,
        'cursor': {'before': 'oldestId', 'after': 'newestId'},
      });
      expect(resp.messages, hasLength(1));
      expect(resp.hasMore, isTrue);
      expect(resp.nextCursor, 'oldestId'); // was null (top-level key) before fix
    });

    test('lifts metadata.modelName onto the message for history', () {
      final resp = MessagesResponse.fromJson({
        'messages': [
          {
            'id': 'm',
            'role': 'assistant',
            'content': 'hello',
            'metadata': {'modelName': 'cyberneurova-qwen'},
          },
        ],
      });
      expect(resp.messages.single.modelName, 'cyberneurova-qwen');
    });
  });
}
