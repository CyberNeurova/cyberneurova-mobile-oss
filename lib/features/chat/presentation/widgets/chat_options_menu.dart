import 'package:cyberneurova_mobile/core/errors/error_messages.dart'
    show userMessageFor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/share_chat_sheet.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/scope_sheet.dart';
import 'package:cyberneurova_mobile/features/projects/data/repositories/project_repository.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/providers/projects_provider.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/screens/projects_screen.dart'
    show projectGlyphIcon;

/// iOS-style popup menu shown from the chat detail's 3-dots button.
/// Floats from the top-right with title header + actions.
Future<void> showChatOptionsMenu({
  required BuildContext context,
  required WidgetRef ref,
  required String chatId,
  required String chatTitle,
  required String currentVisibility,
}) async {
  final cs = Theme.of(context).colorScheme;
  // Scope only means something where device tools can run — the agent
  // surfaces. Offering it in an ordinary chat would imply the agent can reach
  // the user's network from there, which it deliberately cannot.
  final isAgentSession = ref.read(isAgentSessionProvider(chatId));
  // Use a custom showMenu with rounded edges and right-aligned position
  final result = await showMenu<String>(
    context: context,
    color: cs.surfaceContainerHigh,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: cs.outline),
    ),
    position: const RelativeRect.fromLTRB(1000, 64, 16, 0),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        height: 36,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            chatTitle.isEmpty ? 'Untitled' : chatTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      const PopupMenuDivider(height: 1),
      _menuItem(
          value: 'project',
          icon: Icons.folder_outlined,
          label: 'Add to project',
          color: cs.onSurface),
      _menuItem(
          value: 'rename',
          icon: Icons.edit_outlined,
          label: 'Rename',
          color: cs.onSurface),
      _menuItem(
          value: 'share',
          icon: Icons.share_outlined,
          label: 'Share',
          color: cs.onSurface),
      // What the agent may send traffic at in this session. Enforced by the
      // device executor, not merely suggested to the model.
      if (isAgentSession)
        _menuItem(
            value: 'scope',
            icon: Icons.shield_outlined,
            label: 'Agent scope',
            color: cs.onSurface),
      const PopupMenuDivider(height: 1),
      _menuItem(
        value: 'delete',
        icon: Icons.delete_outline,
        label: 'Delete',
        color: cs.error,
      ),
    ],
  );

  if (result == null || !context.mounted) return;
  HapticFeedback.selectionClick();

  switch (result) {
    case 'project':
      await showProjectPicker(context, ref, chatId);
      break;
    case 'rename':
      await _showRenameDialog(context, ref, chatId);
      break;
    case 'share':
      if (context.mounted) {
        await showShareChatSheet(context,
            chatId: chatId, initialVisibility: currentVisibility);
      }
      break;
    case 'scope':
      if (context.mounted) await showScopeSheet(context, chatId);
      break;
    case 'delete':
      await _confirmDelete(context, ref, chatId);
      break;
  }
}

PopupMenuItem<String> _menuItem({
  required String value,
  required IconData icon,
  required String label,
  required Color color,
}) =>
    PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );

// ─── Project picker ──────────────────────────────────────────────────────────

/// Public so the composer's `+` sheet can offer the same action. One picker,
/// two entry points — a second implementation would drift.
Future<void> showProjectPicker(
    BuildContext context, WidgetRef ref, String chatId) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ProjectPicker(chatId: chatId),
  );
}

class _ProjectPicker extends ConsumerWidget {
  const _ProjectPicker({required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final projects = ref.watch(projectsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Add to project',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            projects.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Could not load projects',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            'No projects yet',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              context.pushNamed('profile-projects');
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Create a project'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: list
                          .map((p) => _ProjectRow(
                                icon: projectGlyphIcon(p.icon),
                                name: p.name,
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  try {
                                    await ref
                                        .read(projectRepositoryProvider)
                                        .addChatToProject(p.id, chatId);
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Added to "${p.name}"'),
                                          behavior:
                                              SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(userMessageFor(context, e)),
                                          behavior:
                                              SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow(
      {required this.icon, required this.name, required this.onTap});
  final IconData icon;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Rename dialog ───────────────────────────────────────────────────────────

Future<void> _showRenameDialog(
    BuildContext context, WidgetRef ref, String chatId) async {
  final ctrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Rename chat'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'New title'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final title = ctrl.text.trim();
            if (title.isEmpty) {
              Navigator.pop(dialogCtx);
              return;
            }
            // Capture before the await: dialogCtx disposes the moment we pop,
            // and the outer messenger outlives the dialog so the error is still
            // visible after it closes.
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(dialogCtx);
            try {
              await ref
                  .read(chatRepositoryProvider)
                  .updateChat(chatId, title: title);
              ref.invalidate(chatDetailProvider(chatId));
              ref.invalidate(chatListProvider);
              navigator.pop();
            } catch (e) {
              // Without this, a rejected PATCH threw out of the async onPressed
              // unhandled: the dialog stayed open and nothing changed, so the
              // rename read as "does nothing." Close the dialog and say why.
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(context.mounted
                      ? "Couldn't rename. ${userMessageFor(context, e)}"
                      : "Couldn't rename the chat."),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ─── Delete confirmation ─────────────────────────────────────────────────────
//
// Three bugs the previous version had (all user-reported 2026-06-05):
//
//  1. Buttons frozen. `Navigator.pop(context, ...)` was called with the
//     OUTER context (the chat detail screen) instead of the dialog's
//     own BuildContext, because the builder param was named `_` and
//     discarded. Result: pop walked the wrong route, dialog stayed
//     stuck on screen. Fixed by giving the builder a name (`dialogCtx`)
//     and popping THAT.
//
//  2. Silent failures. The `deleteChat` call had no try/catch, so any
//     server error (403 race, 500, network) bubbled into Flutter's
//     unhandled-error boundary with no UX feedback. Now wrapped + we
//     surface a SnackBar so users see what happened.
//
//  3. "Loops of loading" after barrier-dismiss. If the deleted chat
//     is the one the detail screen is currently displaying, the
//     screen re-fetches on every chat list invalidate and 403s
//     forever. Mitigation: navigate away BEFORE issuing the delete
//     when the current route is `/chats/<chatId>`.

Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, String chatId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Delete chat?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  HapticFeedback.heavyImpact();

  // Capture state we'll need after async work.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final errorColor = Theme.of(context).colorScheme.error;
  final router = GoRouter.of(context);
  final currentRoute = GoRouterState.of(context).matchedLocation;
  final onThisChat = currentRoute.endsWith('/chats/$chatId') ||
      currentRoute.endsWith('/chat/$chatId');

  // Previous attempt popped FIRST then deleted — that race let the
  // bootstrap screen fetch a still-stale chat list (deleted chat
  // still present), route the user back to it, then 403 → bounce →
  // re-fetch → 403 → "loops of loading" the user kept reporting.
  //
  // New order: delete first (server + provider state both updated),
  // THEN navigate. Bootstrap now sees the updated list.

  try {
    await ref.read(chatListProvider.notifier).deleteChat(chatId);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Chat deleted')),
    );

    if (onThisChat) {
      // Navigate to a fresh new chat after deleting the currently-viewed
      // chat — picking the next existing chat felt jarring because the
      // user usually deletes "to start over." Reuses an existing empty
      // chat when one exists (shared new-chat path). Skips
      // ChatBootstrapScreen entirely so its slow path can't trap us in
      // a spinner.
      final fresh =
          await ref.read(chatListProvider.notifier).reuseOrCreateEmptyChat();
      router.goNamed(
        'chat-detail',
        pathParameters: {'id': fresh.id},
      );
    }
  } catch (e) {
    // userMessageFor needs a BuildContext for localization; if the
    // original context tore down during the await, fall back to a
    // plain English message rather than crash.
    final msg =
        context.mounted ? userMessageFor(context, e) : 'Please try again.';
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Could not delete chat: $msg'),
        backgroundColor: errorColor,
      ),
    );
  }
}
