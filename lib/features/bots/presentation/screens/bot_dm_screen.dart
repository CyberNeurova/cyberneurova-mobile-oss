import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/bots/data/bot_turn_runner.dart';
import 'package:cyberneurova_mobile/features/bots/data/repositories/bot_repository.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/providers/bot_attachments_provider.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/providers/bots_providers.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/add_agents_sheet.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/bot_message_view.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/bot_profile_sheet.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/widgets/collaboration_composer.dart';

/// A DM room with one agent contact. Tails the room's `(roomId, seq)` log live
/// (SSE, de-duped) and sends text with an idempotent nonce. Task-turns /
/// approvals / remote-control are P2–P3; P1 is plain conversation.
class BotDmScreen extends ConsumerStatefulWidget {
  const BotDmScreen({
    super.key,
    required this.roomId,
    this.title,
    this.type,
    this.agentId,
  });

  final String roomId;
  final String? title;

  /// `dm` | `group`. A group room exposes the "add agents" + options actions;
  /// a DM exposes a tappable header → the bot's profile.
  final String? type;

  /// The DM's agent, when known — enables the profile view on the header.
  final String? agentId;

  bool get isGroup => type == 'group';

  @override
  ConsumerState<BotDmScreen> createState() => _BotDmScreenState();
}

class _BotDmScreenState extends ConsumerState<BotDmScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  // The title lives in state so a rename updates the app bar immediately.
  late String _title = widget.title ?? (widget.isGroup ? 'Group' : 'Chat');

  @override
  void initState() {
    super.initState();
    // B0: advertise this device as an online executor candidate on room entry,
    // so the estate's presence gate knows mobile can run turns.
    ref.read(botRepositoryProvider).heartbeat().catchError((_) {});
  }

  Future<void> _rename() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: _title),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final room =
          await ref.read(botRepositoryProvider).renameRoom(widget.roomId, name.trim());
      if (!mounted) return;
      setState(() => _title = room?.title ?? name.trim());
      ref.invalidate(botGroupsProvider);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(context, e))));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete group?'),
        content: const Text(
            'This permanently deletes the group and its messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogCtx).colorScheme.error),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(botRepositoryProvider).deleteRoom(widget.roomId);
      ref.invalidate(botGroupsProvider);
      if (mounted) navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(context, e))));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    final blocks =
        ref.read(botAttachmentsProvider(widget.roomId).notifier).toBlocks();
    if (text.trim().isEmpty && blocks.isEmpty) return;
    // History the agent should see = what's in the room BEFORE this send.
    final history = ref.read(botChatProvider(widget.roomId)).messages;
    ref
        .read(botChatProvider(widget.roomId).notifier)
        .send(text, attachmentBlocks: blocks);
    _controller.clear();
    ref.read(botAttachmentsProvider(widget.roomId).notifier).clear();
    _scrollToBottom();
    // PHASE-B: run the agent turn(s) on-device. A DM runs its one agent (B1);
    // a group runs the director → up to two @mentioned responders (B3).
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final runner = ref.read(botTurnRunnerProvider);
    if (widget.isGroup) {
      runner.runGroupTurn(roomId: widget.roomId, userText: trimmed);
    } else if (widget.agentId != null) {
      runner.runTurn(
        roomId: widget.roomId,
        agentId: widget.agentId!,
        userText: trimmed,
        history: history,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(botChatProvider(widget.roomId));

    // Keep the view pinned to the newest message as the tail grows.
    ref.listen<int>(
      botChatProvider(widget.roomId).select((s) => s.messages.length),
      (_, __) => _scrollToBottom(),
    );

    return Scaffold(
      appBar: AppBar(
        title: (!widget.isGroup && widget.agentId != null)
            ? InkWell(
                onTap: () => showBotProfileSheet(context, widget.agentId!),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                        child: Text(_title, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 20),
                  ],
                ),
              )
            : Text(_title),
        actions: [
          if (widget.isGroup) ...[
            IconButton(
              tooltip: 'Add agents',
              icon: const Icon(Icons.group_add_rounded),
              onPressed: () => showAddAgentsSheet(context, widget.roomId),
            ),
            PopupMenuButton<String>(
              tooltip: 'Group options',
              onSelected: (v) => v == 'rename' ? _rename() : _delete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename group')),
                PopupMenuItem(value: 'delete', child: Text('Delete group')),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body(st)),
          if (st.error != null) _ErrorBanner(message: st.error!),
          CollaborationComposer(
            roomId: widget.roomId,
            controller: _controller,
            sending: st.sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _body(BotChatState st) {
    if (st.loading && st.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (st.messages.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Text(
          'No messages yet — say hi.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: st.messages.length,
      itemBuilder: (_, i) => BotMessageView(message: st.messages[i]),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

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
      title: const Text('Rename group'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: 'Group name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        message,
        style: TextStyle(fontSize: 12.5, color: cs.onErrorContainer),
      ),
    );
  }
}

