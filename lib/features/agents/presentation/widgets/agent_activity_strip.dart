import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/agent/agent_outbox.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/agent_session_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/agent_approval_card.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/agent_tool_card.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// The agent's tool activity for one chat.
///
/// ## What stays on screen, and what does not
///
/// Every card used to be rendered inline, stacked under the conversation. On a
/// phone that is most of the screen: four calls in one turn filled it, pushed
/// the terminal out of view, and the cards stayed there afterwards — so you
/// could be in Shell, typing, with a failed `shell_exec` from an earlier Ask
/// turn still sitting above the input.
///
/// The rule now is: **what needs you stays, what happened goes in the panel.**
///
///  - An approval blocks the run until you answer it. Hiding that behind a tap
///    would stall runs invisibly, which is worse than any amount of clutter.
///  - A delivery failure blocks it too, and carries the Retry.
///  - Everything else — running, finished, failed — is history. It gets one
///    line saying how much there is, and opens on tap.
///
/// This is the arrangement the owner asked for, and the reason it is safe is
/// that the two categories are decided by whether the run is waiting on the
/// user, not by how interesting the card looks.
class AgentActivityStrip extends ConsumerWidget {
  const AgentActivityStrip({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(agentSessionProvider(chatId));
    final notifier = ref.read(agentSessionProvider(chatId).notifier);

    final cards = [
      for (final item in session.transcript.items)
        if (item is ToolCardItem) item,
    ];
    if (cards.isEmpty) return const SizedBox.shrink();

    final blocking =
        cards.where((c) => c.state == ToolCardState.approvalRequired).toList();
    final rest = cards
        .where((c) => c.state != ToolCardState.approvalRequired)
        .toList();
    final running =
        rest.where((c) => c.state == ToolCardState.running).length;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Approvals, in full. The run is stopped until one of these is
          // answered, so it is the one thing that must never need a tap to
          // find.
          for (final card in blocking)
            AgentApprovalCard(
              key: ValueKey('approval:${card.callId}'),
              card: card,
              onRespond: (response) => notifier.respondToApproval(
                card.callId,
                decision: response.decision,
                editedInput: response.editedInput,
              ),
            ),

          // Delivery failures are surfaced, never swallowed. A lost approval
          // leaves the run paused indefinitely, so the user has to know —
          // and has to be able to retry.
          if (session.hasFailedControl)
            _ControlFailureBanner(
              entries: session.outbox.entries
                  .where((e) => e.status == OutboxStatus.failed)
                  .toList(),
              onRetry: notifier.retryFailedControl,
            ),

          if (rest.isNotEmpty)
            _ActivitySummaryBar(
              total: rest.length,
              running: running,
              latest: rest.last,
              onTap: () => showAgentActivitySheet(context, chatId),
            ),
        ],
      ),
    );
  }
}

/// One line: how much is happening, and what most recently did.
class _ActivitySummaryBar extends StatelessWidget {
  const _ActivitySummaryBar({
    required this.total,
    required this.running,
    required this.latest,
    required this.onTap,
  });

  final int total;
  final int running;
  final ToolCardItem latest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = running > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              else
                Icon(Icons.build_outlined,
                    size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  // The count is the headline the owner asked for; the name of
                  // the most recent tool is what makes it worth a glance.
                  busy
                      ? '$running running · ${latest.tool}'
                      : '$total tool${total == 1 ? '' : 's'} · ${latest.tool}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: busy ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(Icons.expand_less_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full list, on demand.
Future<void> showAgentActivitySheet(BuildContext context, String chatId) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AgentActivitySheet(chatId: chatId),
  );
}

class _AgentActivitySheet extends ConsumerWidget {
  const _AgentActivitySheet({required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final session = ref.watch(agentSessionProvider(chatId));
    final notifier = ref.read(agentSessionProvider(chatId).notifier);

    final cards = [
      for (final item in session.transcript.items)
        if (item is ToolCardItem) item,
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Text(
                  'Activity',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${cards.length}',
                  style: AppTheme.mono(
                      fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                // Newest first here, unlike the transcript: opening this is
                // asking "what just happened", not "what happened first".
                for (final card in cards.reversed)
                  AgentToolCard(
                    key: ValueKey('sheet:${card.key}'),
                    card: card,
                    onCancel: card.state == ToolCardState.running
                        ? () => notifier.cancel(callId: card.callId)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlFailureBanner extends StatelessWidget {
  const _ControlFailureBanner({required this.entries, required this.onRetry});

  final List<OutboxEntry> entries;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isApproval =
        entries.any((e) => e.message.dedupeKey.startsWith('approval:'));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 17, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isApproval
                  ? "Your decision didn't reach the agent. It's still waiting."
                  : "Couldn't reach the agent.",
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: cs.error,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              onRetry();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
