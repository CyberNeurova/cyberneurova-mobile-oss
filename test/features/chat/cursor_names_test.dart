import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two chat endpoints page on differently-named cursors, and getting it
/// wrong fails SILENTLY.
///
/// A cursor the server does not recognise is ignored, not rejected: the
/// request succeeds, page one comes back again, and the only symptom is a
/// list that will not grow. That has now cost us twice.
///
///  * `/chat/:id/messages` pages on `before`. Sending `startingAfter` there
///    re-served the newest messages for ever.
///  * `/chat` pages on `endingBefore`. The list is newest-first, so the next
///    page is OLDER than the cursor — `startingAfter` asks for NEWER rows,
///    which overlap the page already on screen. That was the other half of
///    "the app can't page past 20 chats": the cursor arrived,
///    the client sent it under the wrong name, and the overlap looked like
///    the server refusing to paginate.
///
/// Three spellings across two routes is enough to keep getting wrong from
/// memory, so this pins each one to its route. There is no runtime seam to
/// assert against — ApiClient owns Dio outright — so this reads the source,
/// which is also where the mistake is made.
void main() {
  final source =
      File('lib/features/chat/data/repositories/chat_repository.dart')
          .readAsStringSync();

  /// The body of a method, from its signature to the closing of its request.
  String bodyOf(String signatureStart) {
    final i = source.indexOf(signatureStart);
    expect(i, isNot(-1), reason: 'method moved or was renamed: $signatureStart');
    final end = source.indexOf('return ', i);
    return source.substring(i, end == -1 ? source.length : end);
  }

  test('the chat LIST pages on endingBefore', () {
    final body = bodyOf('Future<ChatListResponse> listChats(');
    expect(body, contains("'endingBefore': cursor"));
    expect(
      body,
      isNot(contains("'startingAfter'")),
      reason: 'newest-first means the next page is older; startingAfter '
          'returns rows already on screen',
    );
  });

  test('MESSAGES page on before', () {
    final body = bodyOf('Future<MessagesResponse> getMessages(');
    expect(body, contains("'before': cursor"));
    expect(
      body,
      isNot(contains("'endingBefore'")),
      reason: 'that is the list cursor, and this route ignores it',
    );
    expect(body, isNot(contains("'startingAfter'")));
  });

  test('the list asks for a section', () {
    // Without it the page limit is spent across every section at once, which
    // is how Recents came to show two chats out of a twenty-row window.
    expect(
      bodyOf('Future<ChatListResponse> listChats('),
      contains("'section': section"),
    );
  });
}
