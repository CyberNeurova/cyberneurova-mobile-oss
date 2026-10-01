import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/user_model.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/chat_list_cache.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// One row the client cannot read must cost that row, not the chat list.
///
/// The list is four GET /chat requests, one per section, awaited together. The
/// generated page parser threw on a single wrong-typed row, and that one throw
/// rejected all four pages. On a first login there is no cache to fall back
/// on, so the launch screen showed an error and nothing could be opened; with
/// a cache the drawer sat on the saved copy, labelled offline, and never
/// refreshed again.
///
/// These go through the real [ChatRepository] with JSON-decoded bodies, the
/// way Dio hands them over, so the parser is tested where it is used.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The shell page carries one row with `messageCount` as a string, which is
  // what node-postgres returns for a raw COUNT(*).
  const bodies = {
    'chat': '{"chats":[{"id":"c-ok","title":"hello",'
        '"updatedAt":"2026-09-30T10:00:00.000Z"}],"hasMore":false}',
    'code': '{"chats":[{"id":"k-ok","section":"code",'
        '"updatedAt":"2026-09-30T09:00:00.000Z"}],"hasMore":false}',
    'research': '{"chats":[{"id":"r-ok","section":"research",'
        '"updatedAt":"2026-09-30T08:00:00.000Z"}],"hasMore":false}',
    'shell': '{"chats":[{"id":"s-ok","section":"shell",'
        '"updatedAt":"2026-09-30T07:00:00.000Z"},'
        '{"id":"s-bad","section":"shell","messageCount":"12"}],'
        '"hasMore":false}',
  };

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer containerFor(_JsonApi api) {
    final c = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_SignedIn.new),
        chatRepositoryProvider.overrideWithValue(ChatRepository(api)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('with no cache, the readable rows of every section still load',
      () async {
    final c = containerFor(_JsonApi(bodies));
    await c.read(authProvider.future);

    final chats = await c.read(chatListProvider.future);

    expect(chats.map((x) => x.id), ['c-ok', 'k-ok', 'r-ok', 's-ok'],
        reason: 'the bad shell row is dropped; nothing else is');
  });

  test('with a cache, the refresh behind it still lands', () async {
    await ChatListCache.save('u1', const [ChatModel(id: 'old', title: 'old')]);
    final c = containerFor(_JsonApi(bodies));
    await c.read(authProvider.future);

    // The saved copy paints first...
    expect((await c.read(chatListProvider.future)).map((x) => x.id), ['old']);
    // ...and the background refresh then replaces it.
    await pumpEventQueue();

    expect(c.read(chatListProvider).value!.map((x) => x.id),
        ['c-ok', 'k-ok', 'r-ok', 's-ok']);
    expect(c.read(chatListIsStaleProvider), isFalse,
        reason: 'a server that answered is not shown as offline');
    expect((await ChatListCache.load('u1'))!.map((x) => x.id), contains('c-ok'),
        reason: 'and the saved copy is brought up to date');
  });

  test('a drift on every row keeps the saved list instead of wiping it',
      () async {
    // The same wrong type on every row is the server's format changing, not
    // one row. Reading that as "no chats" would replace the saved list with
    // nothing and clear the offline notice.
    String page(String section) => '{"chats":[{"id":"$section-1",'
        '"section":"$section","messageCount":"12"}],"hasMore":false}';
    final drifted = {
      for (final s in ['chat', 'code', 'research', 'shell']) s: page(s),
    };
    await ChatListCache.save('u1', const [ChatModel(id: 'old', title: 'old')]);
    final c = containerFor(_JsonApi(drifted));
    await c.read(authProvider.future);

    expect((await c.read(chatListProvider.future)).map((x) => x.id), ['old']);
    await pumpEventQueue();

    expect(c.read(chatListProvider).value!.map((x) => x.id), ['old']);
    expect(c.read(chatListIsStaleProvider), isTrue,
        reason: 'what is on screen is the saved copy, and says so');
    expect((await ChatListCache.load('u1'))!.map((x) => x.id), ['old'],
        reason: 'the saved copy must survive a response it cannot read');
  });
}

class _SignedIn extends AuthNotifier {
  @override
  Future<UserModel?> build() async =>
      const UserModel(id: 'u1', email: 'u1@example.test');
}

/// Answers GET /chat with a canned JSON body per `section`.
class _JsonApi implements ApiClient {
  _JsonApi(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final section = queryParameters?['section'] as String?;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: jsonDecode(bodies[section] ?? '{"chats":[]}') as T,
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
