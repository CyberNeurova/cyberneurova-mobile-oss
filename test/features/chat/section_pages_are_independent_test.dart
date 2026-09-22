import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// One busy section must not push another one off the phone.
///
/// The owner's report: "the normal chat page doesn't show all chats — on web I
/// have more chats than what's displayed, on the app it only shows 3". Then,
/// after a day of agent testing, two.
///
/// Nothing was lost. The page limit was spent across ALL sections at once, and
/// his newest twenty rows were 14 Console sessions, 4 Research ones and 2
/// chats. Recents filters to `section == 'chat'`, so Recents showed two. No
/// client-side filter could have helped — the chats never arrived.
///
/// The server now paginates within a section (its reply to outbox 064), so the
/// client asks per section and merges. These cases pin the property that
/// matters: what one section does cannot change what another one shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatModel row(String id, String section, {int minutesAgo = 0}) => ChatModel(
        id: id,
        title: '$section $id',
        section: section,
        updatedAt: DateTime(2026, 8, 6, 12).subtract(
          Duration(minutes: minutesAgo),
        ),
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<ChatModel>> listFrom(ChatRepository repo) async {
    final c = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c.read(chatListProvider.future);
  }

  test('a flood of shell sessions cannot evict the chats', () async {
    final repo = _HonoursSection({
      'chat': [row('c1', 'chat', minutesAgo: 90), row('c2', 'chat', minutesAgo: 95)],
      // Every one of these is newer than both chats — under a single global
      // page they took the whole window.
      'shell': [for (var i = 0; i < 14; i++) row('s$i', 'shell', minutesAgo: i)],
      'research': [for (var i = 0; i < 4; i++) row('r$i', 'research', minutesAgo: 20 + i)],
      'code': const [],
    });

    final all = await listFrom(repo);
    final chats = all.where((c) => c.section == 'chat').toList();

    expect(chats.map((c) => c.id), ['c1', 'c2'],
        reason: 'both day-to-day chats survive 14 newer shell sessions');
    expect(all.where((c) => c.section == 'shell'), hasLength(14),
        reason: 'and the shell list is not sacrificed to make room');
  });

  test('every section is asked for, by name', () async {
    final repo = _HonoursSection(const {});
    await listFrom(repo);
    expect(
      repo.asked.toSet(),
      {'chat', 'code', 'research', 'shell'},
      reason: 'a section nobody asks for is a surface that renders empty',
    );
  });

  test('merged rows come back newest first', () async {
    final repo = _HonoursSection({
      'chat': [row('old', 'chat', minutesAgo: 100)],
      'shell': [row('new', 'shell', minutesAgo: 1)],
      'research': [row('mid', 'research', minutesAgo: 50)],
      'code': const [],
    });

    expect((await listFrom(repo)).map((c) => c.id), ['new', 'mid', 'old'],
        reason: 'four pages arrive separately; the list is still one timeline');
  });

  test('a server that ignores the parameter does not quadruple the list',
      () async {
    // The deployment we cannot see from here. If `section` is unknown it comes
    // back as the same unfiltered list four times, and four copies of every
    // row would be a worse bug than the one being fixed.
    final repo = _IgnoresSection([row('a', 'chat'), row('b', 'shell')]);
    expect((await listFrom(repo)).map((c) => c.id), ['a', 'b']);
    expect(repo.calls, 4, reason: 'it was still asked four times');
  });
}

/// Answers only the rows belonging to the requested section.
class _HonoursSection implements ChatRepository {
  _HonoursSection(this.bySection);

  final Map<String, List<ChatModel>> bySection;
  final asked = <String>[];

  @override
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    asked.add(section ?? '<none>');
    return ChatListResponse(chats: bySection[section] ?? const []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Answers the same unfiltered list whatever it is asked for.
class _IgnoresSection implements ChatRepository {
  _IgnoresSection(this.all);

  final List<ChatModel> all;
  int calls = 0;

  @override
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    calls++;
    return ChatListResponse(chats: all);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
