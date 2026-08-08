import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// A single chat row for full-screen chat lists (search results, archived).
///
/// Selection semantics match the drawer's recents exactly — long-press
/// enters selection mode, and once active a plain tap toggles instead of
/// navigating — so the interaction is identical wherever chats are listed.
/// Bulk actions come from [ChatSelectionActionBar]; unlike the drawer rows
/// there's no swipe pane, since these screens have room for a real toolbar.
class ChatListRow extends ConsumerWidget {
  const ChatListRow({
    super.key,
    required this.chat,
    required this.onOpen,
    this.subtitle,
    this.title,
  });

  final ChatModel chat;

  /// Invoked on tap while NOT in selection mode. The host screen decides
  /// what "open" means (the search screen pops itself first, so the chat
  /// doesn't reopen search on back).
  final VoidCallback onOpen;

  /// Optional line under the title — search shows the matched snippet,
  /// archived shows the relative time.
  final String? subtitle;

  /// What to call this row, when the host screen knows better than the chat
  /// does. Agent-session lists say "Untitled session" rather than the chat
  /// wording, because that is what the row is.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedChatsProvider);
    final isSelectionMode = selected.isNotEmpty;
    final isSelected = selected.contains(chat.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? cs.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            if (isSelectionMode) {
              ref.read(selectedChatsProvider.notifier).toggle(chat.id);
              return;
            }
            onOpen();
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            ref.read(selectedChatsProvider.notifier).toggle(chat.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                if (isSelectionMode) ...[
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ??
                            (isPlaceholderChatTitle(chat.title)
                                ? 'New conversation'
                                : chat.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact relative timestamp ("2h ago", "Yesterday", "12 Mar").
String relativeChatTime(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]}';
}
