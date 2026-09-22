import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/providers/bots_providers.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/agent_avatar.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_list_row.dart'
    show relativeChatTime;

/// Bot Chat — the standalone two-pane messenger section (desktop parity:
/// `BOT_CHAT_AND_REMOTE_CONTROL.md` §A, `mobile/desktop/006`). One list with a
/// **Groups** section and a **Direct** section; `+` creates a new group or bot.
/// A group / DM opens the conversation (block rendering + inline approvals +
/// add-agents live there — NOT in Projects).
class BotsScreen extends ConsumerWidget {
  const BotsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(botGroupsProvider);
    final contacts = ref.watch(botContactsProvider);
    final executorOnline =
        ref.watch(botPresenceProvider).valueOrNull?.hasOnlineDesktop ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bot Chat'),
        actions: [
          if (executorOnline)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 4),
                child: _ExecutorChip(),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New',
            onSelected: (v) => v == 'group'
                ? _newGroup(context, ref)
                : _newBot(context, ref),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'group', child: Text('New group')),
              PopupMenuItem(value: 'bot', child: Text('New bot')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.read(botGroupsProvider.notifier).refresh(),
          ref.read(botContactsProvider.notifier).refresh(),
        ]),
        child: _body(context, ref, groups, contacts),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<BotRoom>> groups,
    AsyncValue<List<BotAgent>> contacts,
  ) {
    // The Direct section is always present, so it drives the primary
    // load/error state; a groups fetch failing just hides that section.
    if (contacts.isLoading && !contacts.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (contacts.hasError && !contacts.hasValue) {
      return _MessageState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load Bot Chat",
        body: userMessageFor(context, contacts.error!),
        actionLabel: 'Retry',
        onAction: () => ref.read(botContactsProvider.notifier).refresh(),
      );
    }

    final groupList = groups.valueOrNull ?? const <BotRoom>[];
    final agentList = contacts.valueOrNull ?? const <BotAgent>[];

    if (groupList.isEmpty && agentList.isEmpty) {
      return _MessageState(
        icon: Icons.forum_outlined,
        title: 'No conversations yet',
        body: 'Create a bot to DM, or a group to collaborate with several.',
        actionLabel: 'New bot',
        onAction: () => _newBot(context, ref),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (groupList.isNotEmpty) ...[
          const _SectionHeader('Groups'),
          for (final g in groupList)
            _GroupTile(room: g, onTap: () => _openGroup(context, g)),
        ],
        if (agentList.isNotEmpty) ...[
          const _SectionHeader('Direct'),
          for (final a in agentList)
            _ContactTile(agent: a, onTap: () => _openDm(context, ref, a)),
        ],
      ],
    );
  }

  bool _groupsAllowed(WidgetRef ref) {
    final tier = ref.read(authProvider).valueOrNull?.tier;
    return tier == 'pro' || tier == 'pro_max';
  }

  void _openGroup(BuildContext context, BotRoom room) {
    context.pushNamed(
      'bot-dm',
      pathParameters: {'roomId': room.roomId},
      queryParameters: {'title': room.title ?? 'Group', 'type': 'group'},
    );
  }

  Future<void> _newGroup(BuildContext context, WidgetRef ref) async {
    // Groups are pro/pro_max (engine 403s otherwise); upsell instead of a raw
    // error, as desktop does.
    if (!_groupsAllowed(ref)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Group chats are a Pro / Pro Max feature.'),
          action: SnackBarAction(
            label: 'Upgrade',
            onPressed: () => context.pushNamed('billing-plans'),
          ),
        ),
      );
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(
        title: 'New group',
        label: 'Group name',
        hint: 'e.g. Launch prep',
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      final room =
          await ref.read(botGroupsProvider.notifier).createGroup(title: name.trim());
      if (room != null && context.mounted) {
        _openGroup(context, room);
      }
    } catch (e) {
      _toast(context, userMessageFor(context, e));
    }
  }

  Future<void> _newBot(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(
        title: 'New bot',
        label: 'Name',
        hint: 'e.g. Research assistant',
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      final agent = await ref
          .read(botContactsProvider.notifier)
          .createContact(name: name.trim());
      if (agent != null && context.mounted) {
        await _openDm(context, ref, agent);
      }
    } catch (e) {
      _toast(context, userMessageFor(context, e));
    }
  }

  Future<void> _openDm(
    BuildContext context,
    WidgetRef ref,
    BotAgent agent,
  ) async {
    try {
      final room =
          await ref.read(botContactsProvider.notifier).openDm(agent.agentId);
      if (room == null || !context.mounted) return;
      context.pushNamed(
        'bot-dm',
        pathParameters: {'roomId': room.roomId},
        queryParameters: {'title': agent.name, 'agentId': agent.agentId},
      );
    } catch (e) {
      _toast(context, userMessageFor(context, e));
    }
  }

  void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ExecutorChip extends StatelessWidget {
  const _ExecutorChip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF2FBF71),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('Desktop',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.room, required this.onTap});

  final BotRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cs.primary.withValues(alpha: 0.16),
        child: Icon(Icons.groups_rounded, color: cs.primary),
      ),
      title: Text(room.title ?? 'Group',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        room.updatedAt != null ? relativeChatTime(room.updatedAt) : 'Group',
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.agent, required this.onTap});

  final BotAgent agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = agent.title ?? agent.model;
    return ListTile(
      onTap: onTap,
      leading: AgentAvatar(name: agent.name, avatar: agent.avatar),
      title: Text(agent.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Wrapped in a scroll view so RefreshIndicator can still be pulled when
    // the list is empty.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        Icon(icon, size: 44, color: cs.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 13.5, height: 1.45, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.hint,
  });

  final String title;
  final String label;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
