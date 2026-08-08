import 'package:cyberneurova_mobile/features/chat/data/chat_list_cache.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatModel _chat(String id, String title) => ChatModel(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026, 8, 3),
      updatedAt: DateTime.utc(2026, 8, 3),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips a list', () async {
    await ChatListCache.save('u1', [_chat('a', 'Alpha'), _chat('b', 'Beta')]);
    final got = await ChatListCache.load('u1');
    expect(got, isNotNull);
    expect(got!.map((c) => c.id), ['a', 'b']);
    expect(got.first.title, 'Alpha');
  });

  test('returns null when nothing was cached', () async {
    expect(await ChatListCache.load('nobody'), isNull);
  });

  test('is scoped per user — one account never sees another\'s titles', () async {
    // A shared cache would leak chat TITLES across an account switch. That is
    // a privacy bug, not a staleness bug, so it gets its own test.
    await ChatListCache.save('u1', [_chat('a', 'Private thing')]);
    expect(await ChatListCache.load('u2'), isNull);
  });

  test('caps how much it keeps', () async {
    await ChatListCache.save(
      'u1',
      [for (var i = 0; i < 200; i++) _chat('c$i', 'Chat $i')],
    );
    final got = await ChatListCache.load('u1');
    expect(got!.length, 50);
    expect(got.first.id, 'c0'); // keeps the most recent page, in order
  });

  test('a corrupt entry returns null and clears itself', () async {
    // The stored shape can change between releases. A cache that throws on
    // read would make the app permanently unable to show a list — far worse
    // than losing the cache.
    SharedPreferences.setMockInitialValues({
      'chat_list_cache_v1_u1': 'not json at all',
    });
    expect(await ChatListCache.load('u1'), isNull);
    // And the bad value is gone, so it cannot fail twice.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_list_cache_v1_u1'), isNull);
  });

  test('a JSON value of the wrong shape returns null', () async {
    SharedPreferences.setMockInitialValues({
      'chat_list_cache_v1_u1': '{"not":"a list"}',
    });
    expect(await ChatListCache.load('u1'), isNull);
  });

  test('skips non-map entries instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'chat_list_cache_v1_u1': '[1, "two", null]',
    });
    expect(await ChatListCache.load('u1'), isEmpty);
  });

  test('empty user id is a no-op both ways', () async {
    await ChatListCache.save('', [_chat('a', 'Alpha')]);
    expect(await ChatListCache.load(''), isNull);
  });

  test('clear removes it', () async {
    await ChatListCache.save('u1', [_chat('a', 'Alpha')]);
    await ChatListCache.clear('u1');
    expect(await ChatListCache.load('u1'), isNull);
  });
}
