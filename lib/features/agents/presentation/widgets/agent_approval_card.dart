import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cyberneurova_mobile/core/agent/agent_control.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/tool_presentation.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

class ApprovalResponse {
  const ApprovalResponse({
    required this.decision,
    this.editedInput,
  });

  final ApprovalDecision decision;

  /// Non-null when the user edited the arguments before approving.
  final Map<String, dynamic>? editedInput;
}

/// Inline approval prompt for a tool call the policy engine gated.
///
/// Inline in the transcript, never a modal — a modal interrupts, while a card
/// in the flow lets the user read the agent's reasoning above it before
/// deciding.
///
/// **Edit is the important affordance.** The most common response to an
/// over-broad tool call is not approve or deny, it is "yes, but narrower" —
/// ports 1-1000 instead of 1-65535, these eleven hosts instead of the whole
/// subnet. Without Edit the user denies, retypes their intent as prose, and
/// the agent guesses again.
class AgentApprovalCard extends StatelessWidget {
  const AgentApprovalCard({
    super.key,
    required this.card,
    required this.onRespond,
  });

  final ToolCardItem card;
  final ValueChanged<ApprovalResponse> onRespond;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = ToolPresentation.of(card.tool);
    final rows = toolArgRows(card.input);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.tertiary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.tertiary.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(p.icon, size: 16, color: cs.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'NEEDS APPROVAL',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: cs.tertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Arguments — every one, not a summary. The user is authorising
            // this exact call, so nothing may be hidden behind an expand.
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        row.key,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: cs.onSurface,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (card.rationale case final r? when r.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                r,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onRespond(const ApprovalResponse(
                        decision: ApprovalDecision.approve));
                  },
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onRespond(const ApprovalResponse(
                        decision: ApprovalDecision.approveForSession));
                  },
                  child: const Text('For session'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openEditor(context),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Edit'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onRespond(const ApprovalResponse(
                        decision: ApprovalDecision.deny));
                  },
                  child: const Text('Deny'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    HapticFeedback.selectionClick();
    final edited = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (_) => _ArgumentEditor(tool: card.tool, input: card.input),
    );
    if (edited == null) return;
    onRespond(ApprovalResponse(
      decision: ApprovalDecision.approve,
      editedInput: edited,
    ));
  }
}

/// Edits tool arguments before approving.
///
/// Scalar values get a plain text field; anything structured (a list, a
/// nested object) is edited as JSON, because guessing a form layout for an
/// arbitrary tool schema is not possible — tools can come from MCP servers
/// this build has never seen.
class _ArgumentEditor extends StatefulWidget {
  const _ArgumentEditor({required this.tool, required this.input});
  final String tool;
  final Map<String, dynamic> input;

  @override
  State<_ArgumentEditor> createState() => _ArgumentEditorState();
}

class _ArgumentEditorState extends State<_ArgumentEditor> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, bool> _isStructured;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _isStructured = {};
    for (final entry in widget.input.entries) {
      final v = entry.value;
      final structured = v is Map || v is List;
      _isStructured[entry.key] = structured;
      _controllers[entry.key] = TextEditingController(
        text: structured
            ? const JsonEncoder.withIndent('  ').convert(v)
            : (v?.toString() ?? ''),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rebuilds the argument map, preserving each value's original type so an
  /// edited number does not arrive at the tool as a string.
  void _submit() {
    final out = <String, dynamic>{};
    for (final entry in widget.input.entries) {
      final key = entry.key;
      final text = _controllers[key]!.text;
      final original = entry.value;

      if (_isStructured[key] == true) {
        try {
          out[key] = jsonDecode(text);
        } catch (_) {
          setState(() => _error = 'The value for "$key" is not valid JSON.');
          return;
        }
      } else if (original is int) {
        final parsed = int.tryParse(text.trim());
        if (parsed == null) {
          setState(() => _error = '"$key" must be a whole number.');
          return;
        }
        out[key] = parsed;
      } else if (original is double || original is num) {
        final parsed = double.tryParse(text.trim());
        if (parsed == null) {
          setState(() => _error = '"$key" must be a number.');
          return;
        }
        out[key] = parsed;
      } else if (original is bool) {
        final t = text.trim().toLowerCase();
        out[key] = t == 'true' || t == '1' || t == 'yes';
      } else {
        out[key] = text;
      }
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = ToolPresentation.of(widget.tool);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Edit ${p.label.toLowerCase()}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adjust the arguments, then approve.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final key in widget.input.keys) ...[
                        Text(
                          key,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _controllers[key],
                          maxLines: _isStructured[key] == true ? 6 : null,
                          minLines: 1,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontFamily: _isStructured[key] == true
                                ? 'monospace'
                                : null,
                            color: cs.onSurface,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12.5, color: cs.error),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Approve with changes'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
