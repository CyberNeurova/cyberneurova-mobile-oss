import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';

/// Whether a chat is worth showing in search results.
///
/// Search used to read `plainChatListProvider` and additionally require
/// `messageCount != 0`. Between them, every Console and Research session was
/// invisible: the provider filters to `section == chat`, and agent-run turns
/// are never written server-side, so an agent session's
/// `messageCount` is always 0 no matter how much work is in it.
///
/// Verified on device 2026-08-05: searching "sleep" found nothing while a
/// Console session titled "Run the shell command sleep 30 …" sat two taps
/// away, and neither the Console nor the Research list has a search of its
/// own. Console is the thing this app is for; its work should be findable.
///
/// The blank-chat guard is kept, just expressed by what it was actually for:
/// a chat nobody has spoken in is noise. "No messages" is the wrong test for
/// that — "no messages AND no name" is the right one, and an agent session
/// always has a name because the client titles it from the first thing asked.
bool isSearchable(ChatModel chat) =>
    chat.messageCount != 0 || !isUnusableTitle(chat.title);

/// Which screen opens this chat.
///
/// A Console session lives on `shell-session`, which owns the terminal pane;
/// sending it to `chat-detail` would still work — the surface is resolved from
/// `section`, so the agent keeps its focus and device tools — but the user
/// would lose the terminal half of the session they went looking for.
///
/// Research has no terminal, so `chat-detail` is its real home.
String routeNameForChat(ChatModel chat) =>
    chat.section == AppConstants.sectionShell ? 'shell-session' : 'chat-detail';

/// The surface label shown under a search result, or null for a plain chat.
///
/// Without it, a Console session and a plain chat are two identical rows, and
/// tapping one lands somewhere the other does not.
String? searchSurfaceLabel(ChatModel chat) => switch (chat.section) {
      AppConstants.sectionShell => 'Console',
      AppConstants.sectionResearch => 'Research',
      AppConstants.sectionCode => 'Code',
      _ => null,
    };
