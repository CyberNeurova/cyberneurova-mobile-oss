import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ChatModel _chat(String id, String section) =>
    ChatModel(id: id, title: id, section: section);

/// Agent sessions are ordinary chats with a section tag, so every surface
/// that lists chats shows them unless it filters. The visible symptom was a
/// Console session sitting in the drawer's Recents next to real conversations.
void main() {
  Future<List<ChatModel>?> plainOf(List<ChatModel> all) async {
    final container = ProviderContainer(overrides: [
      chatListProvider.overrideWith(() => _StubChatList(all)),
    ]);
    addTearDown(container.dispose);
    // The notifier builds asynchronously; without this the derived provider
    // is still in its loading state and every expectation sees null.
    await container.read(chatListProvider.future);
    return container.read(plainChatListProvider).valueOrNull;
  }

  test('keeps only plain chats', () async {
    final out = await plainOf([
      _chat('a', AppConstants.sectionChat),
      _chat('b', AppConstants.sectionShell),
      _chat('c', AppConstants.sectionCode),
      _chat('d', AppConstants.sectionResearch),
      _chat('e', AppConstants.sectionChat),
    ]);
    expect(out?.map((c) => c.id), ['a', 'e']);
  });

  test('an unknown section is treated as agent-owned, not plain', () async {
    // A section the server adds before the app knows it must not leak into
    // the drawer.
    final out = await plainOf([
      _chat('a', AppConstants.sectionChat),
      _chat('b', 'some-future-surface'),
    ]);
    expect(out?.map((c) => c.id), ['a']);
  });

  test('all-agent list yields empty, not everything', () async {
    final out = await plainOf([
      _chat('b', AppConstants.sectionShell),
      _chat('c', AppConstants.sectionCode),
    ]);
    expect(out, isEmpty);
  });
}

class _StubChatList extends ChatListNotifier {
  _StubChatList(this._chats);
  final List<ChatModel> _chats;
  @override
  Future<List<ChatModel>> build() async => _chats;
}
