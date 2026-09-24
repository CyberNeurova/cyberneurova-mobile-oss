import 'package:cyberneurova_mobile/features/projects/presentation/screens/projects_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_list_row.dart';
import 'package:cyberneurova_mobile/features/projects/data/models/project_model.dart';
import 'package:cyberneurova_mobile/features/projects/data/repositories/project_repository.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/providers/projects_provider.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Chats belonging to one project, keyed by project id.
final projectChatsProvider =
    FutureProvider.autoDispose.family<List<ChatModel>, String>((ref, id) {
  return ref.read(projectRepositoryProvider).getProjectChats(id);
});

/// A project's contents.
///
/// Tapping a project row used to open the edit sheet — despite the row
/// showing a right-chevron and a chat count, which promises navigation. This
/// is the screen that promise pointed at; editing moved to the overflow menu
/// where destructive/config actions belong.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final chatsAsync = ref.watch(projectChatsProvider(projectId));

    // The list is already in memory from the projects screen; falling back to
    // a placeholder keeps this screen deep-link-safe.
    final project = (ref.watch(projectsProvider).valueOrNull ?? const [])
        .where((p) => p.id == projectId)
        .cast<ProjectModel?>()
        .firstWhere((_) => true, orElse: () => null);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            // Through `projectGlyphIcon`, like the list — one Material icon set,
            // never a raw emoji or the icon NAME the server also stores (which
            // once printed the word "folder" next to the title in the app bar).
            Icon(projectGlyphIcon(project?.icon), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                project?.name ?? 'Project',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.invalidate(projectChatsProvider(projectId));
            },
          ),
        ],
      ),
      body: chatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.refresh(projectChatsProvider(projectId).future),
        ),
        data: (chats) {
          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded,
                        size: 40, color: cs.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No chats in this project',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Long-press chats in the sidebar and use "Add to '
                      'project" to collect them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final chat = chats[i];
              return ChatListRow(
                chat: chat,
                subtitle: relativeChatTime(chat.updatedAt ?? chat.createdAt),
                onOpen: () => context.pushNamed(
                  'chat-detail',
                  pathParameters: {'id': chat.id},
                ),
              );
            },
          );
        },
      ),
    );
  }
}
