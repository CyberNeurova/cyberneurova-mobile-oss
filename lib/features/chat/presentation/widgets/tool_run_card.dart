import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/unified_diff_view.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

// ─── Data model (client-side; parsed from the [TOOL_RUN:{json}] marker) ──────

/// A single tool call inside a completed agentic run.
/// `verb` is one of: run | read | edit | search | fetch.
class ToolRunStep {
  const ToolRunStep({
    required this.verb,
    required this.target,
    this.failed = false,
    this.error,
    this.added,
    this.removed,
    this.diff,
    this.output,
  });

  final String verb;
  final String target;
  final bool failed;
  final String? error;
  final int? added;
  final int? removed;
  final String? diff;

  /// Command stdout, file-content preview, or result summary — shown in the
  /// per-step detail sheet.
  final String? output;

  /// Defensive parse: returns null on anything malformed so a single bad
  /// step never takes the whole run card down.
  static ToolRunStep? fromJson(dynamic json) {
    if (json is! Map) return null;
    final verb = json['verb'];
    final target = json['target'];
    if (verb is! String || verb.isEmpty) return null;
    if (target is! String || target.isEmpty) return null;
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    String? asStr(dynamic v) =>
        v is String && v.isNotEmpty ? v : null;
    return ToolRunStep(
      verb: verb,
      target: target,
      failed: json['failed'] == true,
      error: asStr(json['error']),
      added: asInt(json['added']),
      removed: asInt(json['removed']),
      diff: asStr(json['diff']),
      output: asStr(json['output']),
    );
  }
}

/// A completed agentic tool run — the payload of a `[TOOL_RUN:{json}]`
/// marker embedded in an assistant message.
class ToolRun {
  const ToolRun({required this.steps});

  final List<ToolRunStep> steps;

  /// Defensive parse: malformed steps are skipped; returns null when no
  /// valid step survives (caller renders nothing).
  static ToolRun? fromJson(Map<String, dynamic> json) {
    final raw = json['steps'];
    if (raw is! List) return null;
    final steps = <ToolRunStep>[
      for (final s in raw)
        if (ToolRunStep.fromJson(s) case final step?) step,
    ];
    if (steps.isEmpty) return null;
    return ToolRun(steps: steps);
  }

  int get totalAdded =>
      steps.fold(0, (sum, s) => sum + (s.added ?? 0));
  int get totalRemoved =>
      steps.fold(0, (sum, s) => sum + (s.removed ?? 0));
  int get failedCount => steps.where((s) => s.failed).length;
  bool get hasEdits => steps.any((s) => s.verb == 'edit');

  /// Human summary grouped by verb, in first-appearance order:
  /// "Ran 2 commands · read 3 files · edited app.py".
  String get summary {
    final counts = <String, int>{};
    final order = <String>[];
    for (final s in steps) {
      counts[s.verb] = (counts[s.verb] ?? 0) + 1;
      if (!order.contains(s.verb)) order.add(s.verb);
    }
    String basename(String path) {
      final segments =
          path.split('/').where((p) => p.isNotEmpty).toList();
      return segments.isEmpty ? path : segments.last;
    }
    final parts = <String>[
      for (final verb in order)
        switch (verb) {
          'run' => 'ran ${counts[verb]} command${counts[verb] == 1 ? '' : 's'}',
          'read' => 'read ${counts[verb]} file${counts[verb] == 1 ? '' : 's'}',
          'edit' => counts[verb] == 1
              ? 'edited ${basename(steps.firstWhere((s) => s.verb == 'edit').target)}'
              : 'edited ${counts[verb]} files',
          'search' =>
            counts[verb] == 1 ? 'searched once' : 'searched ${counts[verb]} times',
          'fetch' =>
            'fetched ${counts[verb]} page${counts[verb] == 1 ? '' : 's'}',
          _ => '$verb ${counts[verb]}',
        },
    ];
    if (parts.isEmpty) return 'Tool run';
    final first = parts.first;
    parts[0] = first[0].toUpperCase() + first.substring(1);
    return parts.join(' · ');
  }
}

// ─── Collapsed summary card ──────────────────────────────────────────────────

/// Collapsed one-line summary of an agentic tool run, rendered inline in an
/// assistant message. Tapping opens a bottom-sheet timeline of every step
/// (matching `code_panel.dart`'s sheet chrome); edit steps with a diff
/// payload open the unified diff viewer from there.
class ToolRunCard extends StatelessWidget {
  const ToolRunCard({super.key, required this.run});

  final ToolRun run;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failed = run.failedCount;
    final showBadges =
        run.hasEdits && (run.totalAdded > 0 || run.totalRemoved > 0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _showToolRunSheet(context, run);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: run.summary),
                          if (failed > 0)
                            TextSpan(
                              text: ' · $failed failed',
                              style: TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (showBadges) ...[
                    const SizedBox(width: 8),
                    // No green token in ColorScheme — primary (brand teal)
                    // is the sanctioned green-ish stand-in for "added".
                    _DiffBadge(label: '+${run.totalAdded}', color: cs.primary),
                    const SizedBox(width: 4),
                    _DiffBadge(label: '-${run.totalRemoved}', color: cs.error),
                  ],
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "+12" / "-4" badge used on the collapsed card and edit-step rows.
class _DiffBadge extends StatelessWidget {
  const _DiffBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Light-mode legibility: 11px text in raw light-palette primary/error
    // sits at only ~2.8–3.9:1 on the pale badge tint — deepen it with
    // onSurface ink to clear 4.5:1. Dark keeps the accents untouched
    // (they're already high-contrast on the navy tint).
    final ink = Theme.of(context).brightness == Brightness.light
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.35), color)
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}

// ─── Timeline bottom sheet ───────────────────────────────────────────────────

Future<void> _showToolRunSheet(BuildContext context, ToolRun run) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
    ),
    builder: (_) => _ToolRunSheet(run: run),
  );
}

class _ToolRunSheet extends StatelessWidget {
  const _ToolRunSheet({required this.run});
  final ToolRun run;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = run.steps.length;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle (same as code_panel.dart).
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header: title · step count · close.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Text(
                  'Agent activity',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$n step${n == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              itemCount: run.steps.length,
              itemBuilder: (_, i) => _StepRow(
                step: run.steps[i],
                isFirst: i == 0,
                isLast: i == run.steps.length - 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One timeline row: verb icon in a small circle (connected to neighbors by
/// a thin 1px line), verb + target, optional diff badges, error line under
/// failed steps. Every row is tappable → per-step detail sheet (params,
/// output, and — for edit steps — the unified diff inline).
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.isFirst,
    required this.isLast,
  });

  final ToolRunStep step;
  final bool isFirst;
  final bool isLast;

  static IconData _verbIcon(String verb) => switch (verb) {
        'run' => Icons.terminal_rounded,
        'read' => Icons.visibility_outlined,
        'edit' => Icons.edit_outlined,
        'search' => Icons.search_rounded,
        'fetch' => Icons.language_rounded,
        _ => Icons.build_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = step.failed ? cs.error : cs.primary;
    final hasBadges = step.added != null || step.removed != null;

    Widget connector(bool visible) => visible
        ? Center(
            child: Container(
              width: 1,
              color: cs.outline.withValues(alpha: 0.4),
            ),
          )
        : const SizedBox.shrink();

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _showStepDetailSheet(context, step);
      },
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline gutter: connector · icon circle · connector.
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Expanded(child: connector(!isFirst)),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(_verbIcon(step.verb),
                        size: 14, color: iconColor),
                  ),
                  Expanded(child: connector(!isLast)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          step.verb,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.target,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (hasBadges) ...[
                          const SizedBox(width: 8),
                          // primary = green-ish "added" stand-in (no green
                          // token in ColorScheme).
                          _DiffBadge(
                              label: '+${step.added ?? 0}',
                              color: cs.primary),
                          const SizedBox(width: 4),
                          _DiffBadge(
                              label: '-${step.removed ?? 0}',
                              color: cs.error),
                        ],
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: cs.onSurfaceVariant),
                      ],
                    ),
                    if (step.failed && step.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          step.error!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: cs.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Per-step detail sheet ───────────────────────────────────────────────────

Future<void> _showStepDetailSheet(BuildContext context, ToolRunStep step) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
    ),
    builder: (_) => _StepDetailSheet(step: step),
  );
}

/// Detail view for one tool call: what was targeted (file / command / query)
/// and what came back (output, file content, or — for edits — the unified
/// diff with line numbers). Same sheet chrome as the timeline sheet; the
/// back arrow pops back to it.
class _StepDetailSheet extends StatelessWidget {
  const _StepDetailSheet({required this.step});
  final ToolRunStep step;

  String get _title => switch (step.verb) {
        'run' => 'Ran',
        'read' => 'Read',
        'edit' => 'Edited',
        'search' => 'Searched',
        'fetch' => 'Fetched',
        _ => step.verb.isEmpty
            ? 'Step'
            : step.verb[0].toUpperCase() + step.verb.substring(1),
      };

  String get _paramLabel => switch (step.verb) {
        'read' || 'edit' => 'File',
        'run' => 'Command',
        'search' || 'fetch' => 'Query',
        _ => 'Target',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle (same as the timeline sheet).
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header: back arrow leading + centered title, nothing else.
          SizedBox(
            height: 44,
            child: Stack(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              children: [
                _SectionLabel(_paramLabel),
                _MonoCard(child: _MonoText(step.target)),
                const SizedBox(height: 20),
                ..._buildResultSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResultSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Edit steps: the unified diff, rendered inline with line numbers.
    if (step.verb == 'edit' && step.diff != null) {
      return [
        const _SectionLabel('Output'),
        UnifiedDiffBody(diff: step.diff!),
      ];
    }

    final label = step.verb == 'read' ? 'Content' : 'Output';
    final error = step.failed ? step.error : null;
    final output = step.output;

    if (error == null && output == null) {
      return [
        _SectionLabel(label),
        _MonoCard(
          child: Text(
            'No output',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      ];
    }

    return [
      _SectionLabel(label),
      _MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              _MonoText(error, color: cs.error),
              if (output != null) const SizedBox(height: 8),
            ],
            if (output != null) _MonoText(output),
          ],
        ),
      ),
    ];
  }
}

/// Muted section header — same style as settings_screen.dart's sections.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Rounded monospace container: surfaceContainer fill, radiusMd, thin
/// outline — the shared visual for the param card and output blocks.
class _MonoCard extends StatelessWidget {
  const _MonoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

/// Selectable monospace 13px text used inside [_MonoCard].
class _MonoText extends StatelessWidget {
  const _MonoText(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SelectableText(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: color ?? cs.onSurface,
      ),
    );
  }
}
