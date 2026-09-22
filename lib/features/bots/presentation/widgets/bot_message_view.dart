import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/bots/data/models/bot_models.dart';
import 'package:cyberneurova_mobile/features/bots/data/repositories/bot_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/authed_network_image.dart';

/// Renders one room message: its conversational blocks (text / image /
/// file_ref) inside a chat bubble, plus any typed cards (task_* / question /
/// approval_request / card) as distinct widgets below it. `question` and
/// `approval_request` are interactive — the human answers via an up-lane
/// command bound to the block's run (§5b).
///
/// The design stance (BOT_SECTION_DESIGN §2): "chat + compact cards" — task
/// activity is summarised, not dumped; approvals/questions are inline prompts.
class BotMessageView extends StatelessWidget {
  const BotMessageView({super.key, required this.message});

  final BotMessage message;

  @override
  Widget build(BuildContext context) {
    final fromAgent = message.isFromAgent;

    final convo = <BotBlock>[];
    final cards = <BotBlock>[];
    for (final b in message.blocks) {
      switch (b.type) {
        case 'text':
        case 'image':
        case 'file_ref':
          convo.add(b);
        case 'question':
        case 'approval_request':
        case 'task_started':
        case 'task_progress':
        case 'task_result':
        case 'card':
          cards.add(b);
        default:
          // Forward-compat: an unknown block still shows its text if it has any.
          if (b.displayText != null) convo.add(b);
      }
    }

    final hasConvo = convo.any((b) =>
        b.type == 'image' ||
        b.type == 'file_ref' ||
        (b.displayText?.isNotEmpty ?? false));

    if (!hasConvo && cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment:
          fromAgent ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        if (hasConvo) _Bubble(fromAgent: fromAgent, blocks: convo),
        for (final b in cards) _cardFor(b),
      ],
    );
  }

  Widget _cardFor(BotBlock b) {
    switch (b.type) {
      case 'question':
        return _QuestionCard(message: message, block: b);
      case 'approval_request':
        return _ApprovalCard(message: message, block: b);
      case 'task_started':
      case 'task_progress':
      case 'task_result':
        return _TaskCard(block: b);
      case 'card':
      default:
        return _GenericCard(block: b);
    }
  }
}

// ── Conversational bubble (text / image / file_ref) ─────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromAgent, required this.blocks});

  final bool fromAgent;
  final List<BotBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(6),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: fromAgent ? cs.surfaceContainerHighest : cs.primaryContainer,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(fromAgent ? 4 : 16),
          bottomRight: Radius.circular(fromAgent ? 16 : 4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            fromAgent ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          for (final b in blocks) ..._block(context, b, cs),
        ],
      ),
    );
  }

  List<Widget> _block(BuildContext context, BotBlock b, ColorScheme cs) {
    switch (b.type) {
      case 'image':
        final url = b.fileUrl;
        if (url == null) return const [];
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 260, maxWidth: 240),
                child: AuthedNetworkImage(
                  imageUrl: ApiConstants.resolveImageUrl(url),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ];
      case 'file_ref':
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _FileChip(block: b, onAgentSide: fromAgent),
          ),
        ];
      default:
        final text = b.displayText;
        if (text == null || text.isEmpty) return const [];
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                color: fromAgent ? cs.onSurface : cs.onPrimaryContainer,
              ),
            ),
          ),
        ];
    }
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.block, required this.onAgentSide});

  final BotBlock block;
  final bool onAgentSide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = block.fileName ?? 'File';
    final size = block.sizeBytes;
    final fg = onAgentSide ? cs.onSurface : cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (onAgentSide ? cs.surface : cs.primary).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_rounded, size: 18, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: fg)),
                if (size != null)
                  Text(_fmtSize(size),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: fg.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── task_* card ─────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.block});

  final BotBlock block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = block.type == 'task_result';
    final failed = (block.status ?? '') == 'failed' ||
        (block.status ?? '') == 'error';
    final text = block.displayText ??
        switch (block.type) {
          'task_started' => 'Working…',
          'task_progress' => 'Working…',
          _ => 'Done',
        };

    final (IconData icon, Color tint) = failed
        ? (Icons.error_outline_rounded, cs.error)
        : done
            ? (Icons.check_circle_rounded, cs.primary)
            : (Icons.sync_rounded, cs.onSurfaceVariant);

    return _CardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13.5, height: 1.35, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

// ── card (generic) ──────────────────────────────────────────────────────────

class _GenericCard extends StatelessWidget {
  const _GenericCard({required this.block});

  final BotBlock block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = block.raw['title'];
    final body = block.displayText;
    if ((title is! String || title.isEmpty) && (body == null || body.isEmpty)) {
      return const SizedBox.shrink();
    }
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title is String && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ),
          if (body != null && body.isNotEmpty)
            Text(body,
                style: TextStyle(
                    fontSize: 13.5, height: 1.35, color: cs.onSurface)),
        ],
      ),
    );
  }
}

// ── approval_request (interactive) ──────────────────────────────────────────

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.message, required this.block});

  final BotMessage message;
  final BotBlock block;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _sending = false;
  String? _decision; // 'approved' | 'rejected'
  String? _error;

  String get _runId => widget.block.runIdOr(widget.message.runId);

  Future<void> _decide(bool approve) async {
    if (_sending || _decision != null || _runId.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      // Ratified shape (desktop 004/006): approve/reject carry only the runId.
      final ok = await ref.read(botRepositoryProvider).postCommand(
            widget.message.roomId,
            kind: approve ? 'approve' : 'reject',
            runId: _runId,
            clientNonce:
                '${approve ? 'approve' : 'reject'}-${widget.message.messageId}-${widget.block.refId ?? widget.message.seq}',
          );
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (ok) {
          _decision = approve ? 'approved' : 'rejected';
        } else {
          _error = 'Could not send — try again.';
        }
      });
      if (ok) HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = userMessageFor(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = widget.block.displayText ?? 'Approval requested';
    final risk = widget.block.risk;
    final noRun = _runId.isEmpty;

    return _CardShell(
      tint: cs.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.gpp_maybe_rounded, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Text('Approval needed',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.tertiary)),
              if (risk != null && risk.isNotEmpty) ...[
                const SizedBox(width: 8),
                _RiskChip(risk: risk),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 13.5, height: 1.35, color: cs.onSurface)),
          const SizedBox(height: 10),
          if (_decision != null)
            _DecidedLine(
              icon: _decision == 'approved'
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: _decision == 'approved' ? cs.primary : cs.error,
              label: _decision == 'approved' ? 'Approved' : 'Rejected',
            )
          else if (noRun)
            Text('Waiting for the run to attach…',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : () => _decide(false),
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending ? null : () => _decide(true),
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: TextStyle(fontSize: 12, color: cs.error)),
          ],
        ],
      ),
    );
  }
}

// ── question (interactive) ──────────────────────────────────────────────────

class _QuestionCard extends ConsumerStatefulWidget {
  const _QuestionCard({required this.message, required this.block});

  final BotMessage message;
  final BotBlock block;

  @override
  ConsumerState<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<_QuestionCard> {
  final _freeText = TextEditingController();
  bool _sending = false;
  String? _answered; // the label the human picked / typed
  String? _error;

  String get _runId => widget.block.runIdOr(widget.message.runId);

  @override
  void dispose() {
    _freeText.dispose();
    super.dispose();
  }

  Future<void> _answer(String value, String label,
      {bool freeText = false}) async {
    if (_sending || _answered != null || _runId.isEmpty || value.trim().isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final qid = widget.block.refId;
      final ok = await ref.read(botRepositoryProvider).postCommand(
            widget.message.roomId,
            kind: 'answer',
            runId: _runId,
            // Ratified shape (desktop 004/006): an option pick sends
            // {questionId, optionId}; free-text sends {questionId, text}.
            payload: {
              if (qid != null) 'questionId': qid,
              if (freeText) 'text': value else 'optionId': value,
            },
            clientNonce:
                'answer-${widget.message.messageId}-${qid ?? widget.message.seq}',
          );
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (ok) {
          _answered = label;
        } else {
          _error = 'Could not send — try again.';
        }
      });
      if (ok) HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = userMessageFor(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = widget.block.displayText ?? 'A question for you';
    final options = widget.block.options;
    final noRun = _runId.isEmpty;

    return _CardShell(
      tint: cs.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Question',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 13.5, height: 1.35, color: cs.onSurface)),
          const SizedBox(height: 10),
          if (_answered != null)
            _DecidedLine(
              icon: Icons.check_circle_rounded,
              color: cs.primary,
              label: 'You answered: $_answered',
            )
          else if (noRun)
            Text('Waiting for the run to attach…',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
          else if (options.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in options)
                  OutlinedButton(
                    onPressed:
                        _sending ? null : () => _answer(o.value, o.label),
                    child: Text(o.label),
                  ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _freeText,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) => _answer(v, v, freeText: true),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Type your answer…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending
                      ? null
                      : () =>
                          _answer(_freeText.text, _freeText.text, freeText: true),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.send_rounded, color: cs.primary),
                ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(fontSize: 12, color: cs.error)),
          ],
        ],
      ),
    );
  }
}

// ── shared card chrome ──────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (tint ?? cs.outline).withValues(alpha: 0.35),
        ),
      ),
      child: child,
    );
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.risk});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final high = risk.toLowerCase() == 'high';
    final color = high ? cs.error : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(risk,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _DecidedLine extends StatelessWidget {
  const _DecidedLine(
      {required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
