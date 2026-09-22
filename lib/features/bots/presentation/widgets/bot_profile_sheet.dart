import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/providers/bots_providers.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/agent_avatar.dart';

/// The bot's profile — persona, model, and the capability tool-whitelist the
/// client enforces (§2). Opened by tapping a DM's header (desktop parity §A.2).
Future<void> showBotProfileSheet(BuildContext context, String agentId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BotProfileSheet(agentId: agentId),
  );
}

class _BotProfileSheet extends ConsumerWidget {
  const _BotProfileSheet({required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final agentAsync = ref.watch(botAgentProvider(agentId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: agentAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(userMessageFor(context, e),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          data: (agent) => agent == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('This bot is no longer available.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : _content(context, agent, cs),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, BotAgent agent, ColorScheme cs) {
    final subtitle = agent.title ?? agent.model;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cs.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            AgentAvatar(name: agent.name, avatar: agent.avatar, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(agent.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (agent.model != null && agent.model!.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _Label('Model'),
          const SizedBox(height: 4),
          Text(agent.model!,
              style: TextStyle(fontSize: 14, color: cs.onSurface)),
        ],
        if (agent.description != null && agent.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          const _Label('About'),
          const SizedBox(height: 4),
          Text(agent.description!,
              style: TextStyle(
                  fontSize: 14, height: 1.4, color: cs.onSurface)),
        ],
        if (agent.capabilities.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _Label('Capabilities'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cap in agent.capabilities)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(cap,
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurface)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
