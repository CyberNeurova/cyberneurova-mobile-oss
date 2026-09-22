import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// Pagination must not undo what happened while it was waiting.
///
/// `loadMore` read the list, awaited a page GET, then wrote
/// `[...thatOldList, ...newPage]`. On a slow connection that await is seconds
/// long, and the list is mutated from elsewhere throughout: `createChat`
/// prepends, `deleteChat` removes, `titleFromFirstMessage` rewrites a row.
/// Every one of those was silently reinstated by the stale snapshot.
///
/// From the user's side it is a sidebar that argues with them — delete a chat
/// while the list is loading and it comes back; start a new chat and it is
/// gone from Recents. Both look like a server that ignored the request, which
/// is the wrong place to go looking.
///
/// The mutations themselves were always correct: `createChat` and
/// `deleteChat` each re-read state after their own await. Only the paginator
/// held a snapshot across one.
class _StubRepo implements ChatRepository {
  _StubRepo(this.firstPage);

  final List<ChatModel> firstPage;

  /// Held open so a test can act on the list mid-fetch. That window IS the
  /// bug; a stub that returns immediately cannot express it.
  final page = Completer<ChatListResponse>();
  final deleted = <String>[];

  @override
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    if (cursor == null) {
      return ChatListResponse(
          chats: firstPage, nextCursor: 'c1', hasMore: true);
    }
    return page.future;
  }

  @override
  Future<void> deleteChat(String id) async {
    deleted.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}


/// A server that claims another page and never advances the cursor.
///
/// This is what the real one does today (outbox 061). Wiring pagination up
/// against it filled the drawer with duplicate rows within one scroll — the
/// first page was requested again, appended, and `hasMore` was still true.
class _StuckCursorRepo implements ChatRepository {
  _StuckCursorRepo(this.page);

  final List<ChatModel> page;
  int calls = 0;

  @override
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    calls++;
    // Always the same rows, always "there is more", never a cursor.
    return ChatListResponse(chats: page, hasMore: true);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatModel chat(String id) => ChatModel(id: id, title: 'chat $id');

  late _StubRepo repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _StubRepo([chat('a'), chat('b')]);
    container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // Let build() land the first page.
    await container.read(chatListProvider.future);
  });

  ChatListNotifier notifier() => container.read(chatListProvider.notifier);
  List<String> ids() => [
        for (final c in container.read(chatListProvider).valueOrNull ?? []) c.id
      ];

  test('the first page is what the server sent', () {
    expect(ids(), ['a', 'b']);
  });

  test('a chat deleted mid-fetch does not come back', () async {
    unawaited(notifier().loadMore());
    await Future<void>.delayed(Duration.zero);

    await notifier().deleteChat('a');
    expect(ids(), ['b'], reason: 'the delete itself works');

    // The page the user was scrolling for now arrives.
    repo.page.complete(ChatListResponse(chats: [chat('c')], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ids(), ['b', 'c'],
        reason: 'a resurrected chat reads as a failed delete');
    expect(repo.deleted, ['a']);
  });

  test('a chat created mid-fetch is not swallowed', () async {
    unawaited(notifier().loadMore());
    await Future<void>.delayed(Duration.zero);

    // Straight onto the head of the list, as createChat does after its own
    // await — without going through the network stub.
    container.read(chatListProvider.notifier).state = AsyncData(
        [chat('new'), ...?container.read(chatListProvider).valueOrNull]);

    repo.page.complete(ChatListResponse(chats: [chat('c')], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ids(), ['new', 'a', 'b', 'c'],
        reason: 'a new chat vanishing from Recents looks like it never saved');
  });

  group('a server that never advances the cursor', () {
    late _StuckCursorRepo stuck;
    late ProviderContainer c;

    setUp(() async {
      stuck = _StuckCursorRepo([chat('a'), chat('b')]);
      c = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWithValue(stuck)],
      );
      addTearDown(c.dispose);
      await c.read(chatListProvider.future);
    });

    List<String> stuckIds() => [
          for (final x in c.read(chatListProvider).valueOrNull ?? []) x.id
        ];

    test('does not fill the list with duplicates', () async {
      await c.read(chatListProvider.notifier).loadMore();
      await c.read(chatListProvider.notifier).loadMore();

      expect(stuckIds(), ['a', 'b'],
          reason: 'the same page must not be appended to itself');
    });

    test('stops asking once a page adds nothing', () async {
      final before = stuck.calls;
      await c.read(chatListProvider.notifier).loadMore();
      await c.read(chatListProvider.notifier).loadMore();
      await c.read(chatListProvider.notifier).loadMore();

      // hasMore is only honoured alongside a cursor, so the first loadMore is
      // refused outright and the count never moves.
      expect(stuck.calls, before,
          reason: 'a page it cannot advance past is not worth re-requesting');
    });
  });

  test('an undisturbed page still appends in order', () async {
    unawaited(notifier().loadMore());
    await Future<void>.delayed(Duration.zero);
    repo.page.complete(ChatListResponse(chats: [chat('c')], hasMore: false));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ids(), ['a', 'b', 'c']);
  });
}
