import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/data/repositories/bot_repository.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/providers/bots_providers.dart';

/// Opens the "Add agents" sheet for a collaboration room. Lets the user pick
/// from their agents (or create one) and add them as participants. Adding is
/// idempotent server-side (onConflictDoNothing), so re-adding is harmless.
Future<void> showAddAgentsSheet(BuildContext context, String roomId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddAgentsSheet(roomId: roomId),
  );
}

class _AddAgentsSheet extends ConsumerStatefulWidget {
  const _AddAgentsSheet({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_AddAgentsSheet> createState() => _AddAgentsSheetState();
}

class _AddAgentsSheetState extends ConsumerState<_AddAgentsSheet> {
  final Set<String> _added = {};
  final Set<String> _adding = {};

  Future<void> _add(BotAgent agent) async {
    if (_added.contains(agent.agentId) || _adding.contains(agent.agentId)) {
      return;
    }
    setState(() => _adding.add(agent.agentId));
    try {
      await ref
          .read(botRepositoryProvider)
          .addAgent(widget.roomId, agent.agentId);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        _adding.remove(agent.agentId);
        _added.add(agent.agentId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding.remove(agent.agentId));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessageFor(context, e))));
    }
  }

  Future<void> _newAgent() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewAgentDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final agent = await ref
          .read(botContactsProvider.notifier)
          .createContact(name: name.trim());
      if (agent != null) await _add(agent);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessageFor(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contacts = ref.watch(botContactsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  'Add agents',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _newAgent,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New agent'),
                ),
              ],
            ),
          ),
          Expanded(
            child: contacts.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(userMessageFor(context, e),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
              data: (agents) {
                if (agents.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No agents yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Create an agent to add it to this collaboration.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13.5, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: _newAgent,
                              child: const Text('New agent')),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: agents.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _AgentRow(
                    agent: agents[i],
                    added: _added.contains(agents[i].agentId),
                    adding: _adding.contains(agents[i].agentId),
                    onAdd: () => _add(agents[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.added,
    required this.adding,
    required this.onAdd,
  });

  final BotAgent agent;
  final bool added;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial =
        agent.name.trim().isEmpty ? '?' : agent.name.trim()[0].toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primary.withValues(alpha: 0.16),
        child: Text(initial,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
      ),
      title: Text(agent.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (agent.title ?? agent.model) == null
          ? null
          : Text(agent.title ?? agent.model!,
              maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: adding
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : added
              ? Icon(Icons.check_circle_rounded, color: cs.primary)
              : TextButton(onPressed: onAdd, child: const Text('Add')),
      onTap: added || adding ? null : onAdd,
    );
  }
}

class _NewAgentDialog extends StatefulWidget {
  const _NewAgentDialog();

  @override
  State<_NewAgentDialog> createState() => _NewAgentDialogState();
}

class _NewAgentDialogState extends State<_NewAgentDialog> {
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
      title: const Text('New agent'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Researcher',
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
