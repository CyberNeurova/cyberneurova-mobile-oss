import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';
import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/surface_capabilities_sheet.dart';

/// Agents → Shell. Lists the chats tagged [AppConstants.sectionShell].
///
/// Same shape as the Code list: a session is an ordinary chat with a section
/// tag, so it inherits history, sync and the agent stream for free. The
/// difference is what opens — a terminal workspace rather than a chat thread.
class ShellSessionsScreen extends ConsumerStatefulWidget {
  const ShellSessionsScreen({super.key});

  @override
  ConsumerState<ShellSessionsScreen> createState() =>
      _ShellSessionsScreenState();
}

class _ShellSessionsScreenState extends ConsumerState<ShellSessionsScreen> {
  bool _creating = false;

  Future<void> _newSession() async {
    if (_creating) return;
    HapticFeedback.mediumImpact();
    setState(() => _creating = true);
    try {
      final chat = await ref
          .read(chatListProvider.notifier)
          .createChat(section: AppConstants.sectionShell);
      if (!mounted) return;
      context.pushNamed('shell-session', pathParameters: {'id': chat.id});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // `$e` here appended the raw exception to a friendly prefix —
          // "Couldn't start a shell session: SocketException: ..." is not
          // a friendlier message, it is a stack trace with a preamble.
          content: Text("Couldn't start a shell session. "
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
    final chats = chatsAsync.valueOrNull;
    final sessions = chats
            ?.where(
                (c) => c.section == AppConstants.sectionShell)
            .toList() ??
        const [];

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Console'),
        actions: [
          const SurfaceCapabilitiesAction(surface: AgentSurface.console),
          IconButton(
            tooltip: 'Console setup',
            icon: const Icon(Icons.tune_rounded),
            // Where a distro gets installed. This was an adb property, which
            // is fine for us and useless to a user — and "install what you
            // need" is the whole promise, so it has to be reachable.
            onPressed: () => context.pushNamed('agent-environment'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _newSession,
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_rounded),
        label: Text(_creating ? 'Starting…' : 'New session'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      // Loading and failure must NOT both collapse into the empty state.
      // `valueOrNull` is null for either, and rendering "No sessions yet" for
      // a request that is still in flight — or one that failed — tells the
      // user their sessions are gone when they are not.
      body: chats == null && chatsAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : chats == null && chatsAsync.hasError
              ? ErrorView(
                  error: chatsAsync.error!,
                  onRetry: () => ref.invalidate(chatListProvider),
                )
              : sessions.isEmpty
          ? _Empty(onCreate: _creating ? null : _newSession)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final chat = sessions[i];
                return _SessionRow(
                  title: sessionDisplayTitle(chat.title),
                  onTap: () => context.pushNamed(
                    'shell-session',
                    pathParameters: {'id': chat.id},
                  ),
                );
              },
            ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.data_object_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_object_rounded, size: 40, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'No shell sessions',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A terminal you can also talk to. You and the agent share one '
              'session, one directory and one scrollback.',
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
}
