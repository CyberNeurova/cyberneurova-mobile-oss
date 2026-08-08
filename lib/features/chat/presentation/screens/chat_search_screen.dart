import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_search_routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/archived_chats_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_list_row.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_selection_bar.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Full-screen chat search that doubles as a management surface.
///
/// Replaces the old `SearchDelegate`, which could only navigate: you found a
/// chat and that was it. Real cleanup usually starts with a search ("delete
/// everything about X"), so results here support the same long-press
/// multi-select as the drawer, with archive and delete in the toolbar.
class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Selection is global state; a stale selection from the drawer would
    // otherwise show this screen already in selection mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(selectedChatsProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Case-insensitive match over title and last-message preview.
  List<ChatModel> _filter(List<ChatModel> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return [
      for (final c in all)
        if (c.title.toLowerCase().contains(q) ||
            (c.lastMessage ?? '').toLowerCase().contains(q))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Every section, not just plain chats — see `isSearchable`.
    final chatsAsync = ref.watch(chatListProvider);
    final archived = ref.watch(archivedChatsProvider);

    // Blank chats are noise in search; archived ones live on their own
    // screen. Both stay reachable there rather than cluttering results.
    final all = [
      for (final c in chatsAsync.valueOrNull ?? const <ChatModel>[])
        if (isSearchable(c) && !archived.contains(c.id)) c,
    ];
    final results = _filter(all);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 16, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Search chats…',
            hintStyle: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                HapticFeedback.selectionClick();
                _controller.clear();
                setState(() => _query = '');
                _focus.requestFocus();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          ChatSelectionActionBar(
            visibleChatIds: [for (final c in results) c.id],
          ),
          Expanded(
            // Guard on the value, not the flag. `isLoading` alone meant a
            // background refresh wiped the results out from under whoever was
            // mid-search, and because `valueOrNull` is null on failure too, a
            // broken load reached the "no matches" state — which reads as "you
            // have no chat called that", the one conclusion it must not invite.
            child: chatsAsync.isLoading && chatsAsync.valueOrNull == null
                ? const Center(child: CircularProgressIndicator())
                : chatsAsync.hasError && chatsAsync.valueOrNull == null
                    ? ErrorView(
                        error: chatsAsync.error!,
                        onRetry: () => ref.invalidate(chatListProvider),
                      )
                    : results.isEmpty
                        ? _EmptyState(query: _query)
                        : ListView.builder(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final chat = results[i];
                              final label = searchSurfaceLabel(chat);
                              final when = relativeChatTime(
                                  chat.updatedAt ?? chat.createdAt);
                              return ChatListRow(
                                chat: chat,
                                subtitle:
                                    label == null ? when : '$label · $when',
                                onOpen: () {
                                  // Pop first so Back from the chat returns to
                                  // the app, not to a stale search field.
                                  context.pop();
                                  context.goNamed(
                                    routeNameForChat(chat),
                                    pathParameters: {'id': chat.id},
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final searching = query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 40,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'No chats match "$query"' : 'No chats yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
