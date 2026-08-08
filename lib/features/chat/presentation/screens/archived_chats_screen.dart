import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/archived_chats_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_list_row.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_selection_bar.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Settings → Archived chats.
///
/// Archived chats used to be reachable only through a collapsed group buried
/// under the drawer's recents, which is hard to find and offers no bulk
/// actions. This gives them a real home with the same long-press
/// multi-select as everywhere else — except Archive is swapped for
/// Unarchive.
///
/// Archiving is device-local for now (see [archivedChatsProvider]); the ids
/// are intersected with the live chat list, so anything deleted elsewhere
/// simply stops appearing.
class ArchivedChatsScreen extends ConsumerStatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  ConsumerState<ArchivedChatsScreen> createState() =>
      _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends ConsumerState<ArchivedChatsScreen> {
  @override
  void initState() {
    super.initState();
    // Selection is global; clear anything carried in from the drawer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(selectedChatsProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chatsAsync = ref.watch(plainChatListProvider);
    final archivedIds = ref.watch(archivedChatsProvider);

    final chats = [
      for (final c in chatsAsync.valueOrNull ?? const <ChatModel>[])
        if (archivedIds.contains(c.id)) c,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Archived chats'),
      ),
      body: Column(
        children: [
          ChatSelectionActionBar(
            visibleChatIds: [for (final c in chats) c.id],
            archiveAction: ArchiveAction.unarchive,
          ),
          Expanded(
            // `valueOrNull` is null both while loading and on failure, so a
            // failed load rendered "No archived chats" — telling someone
            // their archive is empty when the request simply broke. Guard on
            // the value, not on the flag: a refresh is `isLoading` too, and
            // blanking a list the user is already reading is its own bug.
            child: chatsAsync.isLoading && chatsAsync.valueOrNull == null
                ? const Center(child: CircularProgressIndicator())
                : chatsAsync.hasError && chatsAsync.valueOrNull == null
                    ? ErrorView(
                        error: chatsAsync.error!,
                        onRetry: () => ref.invalidate(plainChatListProvider),
                      )
                    : chats.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.archive_outlined,
                                      size: 40, color: cs.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No archived chats',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: cs.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Swipe a chat in the sidebar, or long-press to '
                                    'select several, to archive them here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: cs.onSurfaceVariant,
                                        height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: chats.length,
                            itemBuilder: (_, i) {
                              final chat = chats[i];
                              return ChatListRow(
                                chat: chat,
                                subtitle: relativeChatTime(
                                    chat.updatedAt ?? chat.createdAt),
                                onOpen: () {
                                  context.pop();
                                  context.goNamed(
                                    'chat-detail',
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
