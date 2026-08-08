import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/archived_chats_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// Bulk-action bar shown whenever [selectedChatsProvider] is non-empty.
///
/// Shared by every surface that lists chats — the drawer recents, the search
/// screen, and the archived screen — so "long-press to select" behaves
/// identically wherever the user happens to be. Each surface passes the ids
/// it currently shows so "Select all" can act on the right scope, and opts
/// in to the actions that make sense there (the archived screen swaps
/// Archive for Unarchive; only the drawer offers Add to project).
class ChatSelectionActionBar extends ConsumerWidget {
  const ChatSelectionActionBar({
    super.key,
    required this.visibleChatIds,
    this.onAddToProject,
    this.archiveAction = ArchiveAction.archive,
  });

  /// Everything currently listed on the host surface — the scope for
  /// "Select all".
  final List<String> visibleChatIds;

  /// Omitted on surfaces where project assignment doesn't apply.
  final void Function(Set<String> ids)? onAddToProject;

  final ArchiveAction archiveAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChatsProvider);
    if (selected.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final allSelected = visibleChatIds.isNotEmpty &&
        visibleChatIds.every(selected.contains);
    final isArchiving = archiveAction == ArchiveAction.archive;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel',
            icon: Icon(Icons.close_rounded, color: cs.onSurface),
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(selectedChatsProvider.notifier).clear();
            },
          ),
          Text(
            '${selected.length} selected',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          if (visibleChatIds.isNotEmpty)
            IconButton(
              tooltip: allSelected ? 'Deselect all' : 'Select all',
              icon: Icon(
                allSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                color: cs.onSurface,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                final notifier = ref.read(selectedChatsProvider.notifier);
                allSelected
                    ? notifier.clear()
                    : notifier.selectAll(visibleChatIds);
              },
            ),
          IconButton(
            tooltip: isArchiving ? 'Archive' : 'Unarchive',
            icon: Icon(
              isArchiving
                  ? Icons.archive_outlined
                  : Icons.unarchive_outlined,
              color: cs.onSurface,
            ),
            onPressed: () =>
                bulkSetArchived(context, ref, selected, archived: isArchiving),
          ),
          if (onAddToProject != null)
            IconButton(
              tooltip: 'Add to project',
              icon: Icon(Icons.folder_outlined, color: cs.onSurface),
              onPressed: () => onAddToProject!(selected),
            ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
            onPressed: () => bulkDeleteChats(context, ref, selected),
          ),
        ],
      ),
    );
  }
}

enum ArchiveAction { archive, unarchive }

/// Archive (or unarchive) every id in [ids], then leave selection mode.
///
/// Archiving is device-local for now (see [archivedChatsProvider]) so this
/// never fails — no confirmation dialog, just an undoable snackbar.
Future<void> bulkSetArchived(
  BuildContext context,
  WidgetRef ref,
  Set<String> ids, {
  required bool archived,
}) async {
  if (ids.isEmpty) return;
  HapticFeedback.mediumImpact();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final notifier = ref.read(archivedChatsProvider.notifier);
  final affected = ids.toList();

  for (final id in affected) {
    archived ? await notifier.archive(id) : await notifier.unarchive(id);
  }
  ref.read(selectedChatsProvider.notifier).clear();

  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        '${affected.length} chat${affected.length == 1 ? '' : 's'} '
        '${archived ? 'archived' : 'unarchived'}',
      ),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          for (final id in affected) {
            archived
                ? await notifier.unarchive(id)
                : await notifier.archive(id);
          }
        },
      ),
    ),
  );
}

/// Confirm-then-delete every id in [ids]. If the user is currently viewing
/// one of them, they're moved to a fresh chat afterwards.
Future<void> bulkDeleteChats(
  BuildContext context,
  WidgetRef ref,
  Set<String> ids,
) async {
  if (ids.isEmpty) return;
  final cs = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(
          'Delete ${ids.length} chat${ids.length == 1 ? '' : 's'}?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text('Delete', style: TextStyle(color: cs.error)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  HapticFeedback.heavyImpact();

  final messenger = ScaffoldMessenger.maybeOf(context);
  final listNotifier = ref.read(chatListProvider.notifier);
  final archivedNotifier = ref.read(archivedChatsProvider.notifier);
  final router = GoRouter.of(context);
  final currentRoute = GoRouterState.of(context).matchedLocation;
  final viewingDeleted = ids.any((id) =>
      currentRoute.endsWith('/chats/$id') ||
      currentRoute.endsWith('/chat/$id'));

  // Sequential, not Future.wait: each delete mutates the same
  // chatListProvider state object, and concurrent mutations would drop
  // every result but the last.
  var ok = 0;
  var failed = 0;
  for (final id in ids) {
    try {
      await listNotifier.deleteChat(id);
      // Keep the device-local archive set from accumulating dead ids.
      await archivedNotifier.unarchive(id);
      ok++;
    } catch (_) {
      failed++;
    }
  }
  ref.read(selectedChatsProvider.notifier).clear();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
          failed == 0 ? '$ok chats deleted' : '$ok deleted, $failed failed'),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // If the user was looking at one of the chats we just nuked, send them to
  // a fresh chat (same UX as single-delete). Reuses an existing empty chat
  // rather than always minting a new record.
  if (viewingDeleted) {
    try {
      final fresh = await listNotifier.reuseOrCreateEmptyChat();
      router.goNamed('chat-detail', pathParameters: {'id': fresh.id});
    } catch (_) {
      // reuse/create failed — the user is on a stale chat-detail route but
      // the chat list is intact; any drawer row recovers them.
    }
  }
}
