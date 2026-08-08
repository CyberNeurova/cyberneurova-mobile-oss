import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_list_row.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_selection_bar.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';
import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/surface_capabilities_sheet.dart';

/// Agents → Code. Lists the chats tagged [AppConstants.sectionCode], each of
/// which is one coding session.
///
/// Sessions are ordinary chats with a `section` tag rather than a separate
/// entity, so they inherit streaming, attachments, history and the shared
/// long-press multi-select for free. The richer "working directory" model —
/// a file tree per project plus a log of changes — needs backend that doesn't
/// exist yet; this is the surface it will grow into.
class CodeSessionsScreen extends ConsumerStatefulWidget {
  const CodeSessionsScreen({super.key});

  @override
  ConsumerState<CodeSessionsScreen> createState() => _CodeSessionsScreenState();
}

class _CodeSessionsScreenState extends ConsumerState<CodeSessionsScreen> {
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // Selection is global state; clear anything carried in from the drawer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(selectedChatsProvider.notifier).clear();
    });
  }

  Future<void> _newSession() async {
    if (_creating) return;
    HapticFeedback.mediumImpact();
    setState(() => _creating = true);
    try {
      final chat = await ref
          .read(chatListProvider.notifier)
          .createChat(section: AppConstants.sectionCode);
      if (!mounted) return;
      context.pushNamed('chat-detail', pathParameters: {'id': chat.id});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't start a code session. "
              '${userMessageFor(context, e)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chatsAsync = ref.watch(chatListProvider);
    final sessions = [
      for (final c in chatsAsync.valueOrNull ?? const <ChatModel>[])
        if (c.section == AppConstants.sectionCode) c,
    ];

    // The empty state carries its own "New session" button, so showing the FAB
    // as well put two identical buttons on one otherwise blank screen — the
    // user has to work out whether they do the same thing. The empty state
    // wins there because it sits with the sentence explaining what a session
    // is; the FAB wins once there is a list to keep clear of.
    final showFab = sessions.isNotEmpty;

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _creating ? null : _newSession,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              icon: _creating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_creating ? 'Starting…' : 'New session'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Text(
                    'Code',
                    style: AppTheme.serifDisplay(size: 22, color: cs.onSurface),
                  ),
                  const Spacer(),
                  // The placeholder that balanced the back button now earns
                  // its space: what this surface can actually do is the one
                  // thing the screen never said.
                  const SurfaceCapabilitiesAction(surface: AgentSurface.code),
                ],
              ),
            ),
            ChatSelectionActionBar(
              visibleChatIds: [for (final c in sessions) c.id],
            ),
            Expanded(
              // Same trap as the Console list: valueOrNull is null while
              // LOADING and on FAILURE, so both used to render as "no
              // sessions yet" — telling the user their work is gone when
              // the request simply had not finished.
              //
              // Both halves of each guard matter. An unguarded `isLoading`
              // sat in front of this ladder and made every branch below it
              // unreachable, so the error case never rendered — and because
              // a refresh is also `isLoading` with data already in hand, the
              // whole list blanked to a spinner every time it reloaded.
              child: chatsAsync.isLoading && chatsAsync.valueOrNull == null
                  ? const Center(child: CircularProgressIndicator())
                  : chatsAsync.hasError && chatsAsync.valueOrNull == null
                      ? ErrorView(
                          error: chatsAsync.error!,
                          onRetry: () => ref.invalidate(chatListProvider),
                        )
                      : sessions.isEmpty
                          ? _EmptyCode(
                              onCreate: _creating ? null : _newSession,
                              creating: _creating,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                              itemCount: sessions.length,
                              itemBuilder: (_, i) {
                                final chat = sessions[i];
                                return ChatListRow(
                                  chat: chat,
                                  title: sessionDisplayTitle(chat.title),
                                  subtitle: relativeChatTime(
                                      chat.updatedAt ?? chat.createdAt),
                                  onOpen: () => context.pushNamed(
                                    'chat-detail',
                                    pathParameters: {'id': chat.id},
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCode extends StatelessWidget {
  const _EmptyCode({required this.onCreate, this.creating = false});
  final VoidCallback? onCreate;
  final bool creating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              'No code sessions yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a session to build something — the agent keeps the whole '
              'project in context across turns.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(creating ? 'Starting…' : 'New session'),
            ),
          ],
        ),
      ),
    );
  }
}
