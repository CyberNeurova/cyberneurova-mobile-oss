import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/tool_presentation.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/line_diff.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/diff_body.dart';

/// Renders one tool call in the transcript, in any state.
///
/// Deliberately generic: it takes a tool name, an argument map and a state,
/// and never switches on the specific tool. That is what lets the agent use
/// a tool the app has never heard of — including one added by an MCP server
/// after this build shipped — and still show the user something useful.
///
/// Collapsed by default once finished; a running card shows a live tail so
/// the user can see work happening rather than a spinner.
class AgentToolCard extends StatefulWidget {
  const AgentToolCard({
    super.key,
    required this.card,
    this.onCancel,
    this.onRetry,
  });

  final ToolCardItem card;
  final VoidCallback? onCancel;

  /// Offered only for a tool THIS device can run. A server-side tool ran
  /// somewhere the app cannot reach, so a retry button would be a lie.
  final VoidCallback? onRetry;

  @override
  State<AgentToolCard> createState() => _AgentToolCardState();
}

class _AgentToolCardState extends State<AgentToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = widget.card;
    final p = ToolPresentation.of(card.tool);
    final argSummary = summarizeToolArgs(card.input, p);
    final accent = _accent(cs, card.state);

    // A file edit's output IS a unified diff (see FileWriteTool). Reading the
    // shape rather than switching on the tool name keeps this working for a
    // tool the app has never heard of — including one an MCP server added
    // after this build shipped.
    final output = card.output;
    final isDiff = output != null && looksLikeDiff(output);
    final stat = isDiff ? DiffStat.parse(output) : null;

    return Padding(
      // Density pass. Measured on the SM-A546E: a collapsed card was 178px,
      // about 63dp, for a row that says "Port scan failed / 9.9.9.9 / 0s". On
      // a phone that is a list where four entries fill the screen, which is
      // the owner's complaint — "look how big the drop downs are, picture a
      // scenario where we have more than 50 actions". Target is a scannable
      // ~48dp row that still has room to breathe.
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _canExpand ? _toggle : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StateGlyph(state: card.state, icon: p.icon, accent: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.title ?? _headline(card, p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: cs.onSurface,
                            ),
                          ),
                          if (stat != null && !stat.isEmpty) ...[
                            const SizedBox(height: 3),
                            // The size of the change, without expanding. In a
                            // list of twenty edits this is what separates the
                            // one worth reading from the nineteen that are not.
                            DiffStatChip(stat: stat),
                          ],
                          if (argSummary != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              argSummary,
                              maxLines: _expanded ? 4 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.2,
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Trailing(
                      card: card,
                      accent: accent,
                      expanded: _expanded,
                      canExpand: _canExpand,
                      onCancel: widget.onCancel,
                    ),
                  ],
                ),

                // Live tail while running — the point is to show motion, so
                // only the last few lines, monospaced, dimmed.
                if (card.state == ToolCardState.running &&
                    card.progressLines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LiveTail(lines: card.progressLines),
                ],

                if (_expanded) ...[
                  const SizedBox(height: 10),
                  _ExpandedDetail(card: card),
                ],

                if (card.state == ToolCardState.failed) ...[
                  if (card.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      card.error!,
                      style:
                          TextStyle(fontSize: 12, color: cs.error, height: 1.4),
                    ),
                  ],
                  // Most device failures are transient in a way the model
                  // cannot see — a scan that raced the Wi-Fi returning, a
                  // probe against a sleeping host, a write during extraction.
                  // Its only recovery is to decide again, which costs a turn
                  // and often produces a worse plan. The user can see the
                  // phone simply was not ready.
                  if (widget.onRetry != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.onRetry!.call();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 15),
                        label: const Text('Run again'),
                      ),
                    ),
                  ],
                ],

                if (card.artifacts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in card.artifacts) _ArtifactChip(artifact: a),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _canExpand {
    final c = widget.card;
    return c.input.isNotEmpty ||
        (c.output?.isNotEmpty ?? false) ||
        c.progressLines.isNotEmpty;
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  String _headline(ToolCardItem card, ToolPresentation p) =>
      switch (card.state) {
        ToolCardState.pending => p.label,
        ToolCardState.running => p.runningVerb,
        ToolCardState.approvalRequired => '${p.label} — needs approval',
        ToolCardState.succeeded => card.summary ?? p.label,
        ToolCardState.failed => '${p.label} failed',
        ToolCardState.denied => '${p.label} — denied',
        ToolCardState.cancelled => '${p.label} — cancelled',
      };

  Color _accent(ColorScheme cs, ToolCardState state) => switch (state) {
        ToolCardState.failed => cs.error,
        ToolCardState.denied => cs.error,
        ToolCardState.cancelled => cs.outline,
        ToolCardState.approvalRequired => cs.tertiary,
        ToolCardState.succeeded => cs.primary,
        _ => cs.primary,
      };
}

class _StateGlyph extends StatelessWidget {
  const _StateGlyph({
    required this.state,
    required this.icon,
    required this.accent,
  });

  final ToolCardState state;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (state == ToolCardState.running)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: accent.withValues(alpha: 0.7),
              ),
            ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Icon(
              switch (state) {
                ToolCardState.succeeded => Icons.check_rounded,
                ToolCardState.failed => Icons.close_rounded,
                ToolCardState.denied => Icons.block_rounded,
                ToolCardState.cancelled => Icons.remove_rounded,
                ToolCardState.approvalRequired => Icons.lock_outline_rounded,
                _ => icon,
              },
              size: 13,
              color: state == ToolCardState.cancelled
                  ? cs.onSurfaceVariant
                  : accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.card,
    required this.accent,
    required this.expanded,
    required this.canExpand,
    this.onCancel,
  });

  final ToolCardItem card;
  final Color accent;
  final bool expanded;
  final bool canExpand;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (card.state == ToolCardState.running && onCancel != null) {
      final elapsed = card.elapsed;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (elapsed != null) _Elapsed(elapsed: elapsed),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Stop',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(Icons.stop_circle_outlined,
                size: 18, color: cs.onSurfaceVariant),
            onPressed: () {
              HapticFeedback.mediumImpact();
              onCancel!();
            },
          ),
        ],
      );
    }

    final elapsed = card.elapsed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (card.state.isTerminal && elapsed != null)
          _Elapsed(elapsed: elapsed),
        if (canExpand) ...[
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(Icons.expand_more_rounded,
                size: 18, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _Elapsed extends StatelessWidget {
  const _Elapsed({required this.elapsed});
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = elapsed.inSeconds;
    final label = s < 60 ? '${s}s' : '${elapsed.inMinutes}m ${s % 60}s';
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: cs.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _LiveTail extends StatelessWidget {
  const _LiveTail({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Last few lines only — enough to read as motion, not enough to
    // dominate the transcript.
    final tail = lines.length > 4 ? lines.sublist(lines.length - 4) : lines;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in tail)
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpandedDetail extends StatelessWidget {
  const _ExpandedDetail({required this.card});
  final ToolCardItem card;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = toolArgRows(card.input);
    final output = card.output;
    final isDiff = output != null && looksLikeDiff(output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isNotEmpty) ...[
          Text(
            'ARGUMENTS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      row.key,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      row.value,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: cs.onSurface,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (output != null && output.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                isDiff ? 'CHANGES' : 'OUTPUT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Selecting a wall of monospace by dragging on a phone is a
              // losing game, and this output is exactly what people want to
              // paste somewhere else.
              _CopyButton(text: output),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppTheme.radiusXs),
            ),
            // Horizontally scrollable: tool output is full of long paths, and
            // wrapping them makes a listing unreadable. The transcript itself
            // must never scroll sideways, so the overflow is confined here.
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: isDiff
                    ? DiffBody(output)
                    : SelectableText(
                        output,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.5,
                          color: cs.onSurface,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One-tap copy for a block of tool output.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        HapticFeedback.lightImpact();
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.copy_rounded, size: 14, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _ArtifactChip extends StatelessWidget {
  const _ArtifactChip({required this.artifact});
  final AgentArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          // Preview lands with the artifact/file model — see docs/TODO.md 2.x.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(artifact.name),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attachment_rounded, size: 13, color: cs.primary),
              const SizedBox(width: 6),
              // Bounded and elided. An artifact name is often a full path —
              // `data/data/ai.cyberneurova.app/app_flutter/...` — and an
              // unconstrained Text in a min-size Row runs straight off the
              // card, which Flutter paints as overflow tape across the chip.
              Flexible(
                child: Text(
                  artifact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
