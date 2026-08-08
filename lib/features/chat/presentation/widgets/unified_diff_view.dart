import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Full-screen unified diff viewer — same sheet chrome as `code_panel.dart`'s
/// [showCodePanel] (drag handle, rounded top corners, header + close, inner
/// "panel" container) so agentic diffs feel native to the existing code UI.
///
/// The body itself is [UnifiedDiffBody], reused by the per-step detail sheet
/// in `tool_run_card.dart` so edit steps render the same diff inline.
Future<void> showUnifiedDiff(
  BuildContext context, {
  required String fileName,
  required String diff,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
    ),
    builder: (_) => _UnifiedDiffSheet(fileName: fileName, diff: diff),
  );
}

class _UnifiedDiffSheet extends StatelessWidget {
  const _UnifiedDiffSheet({required this.fileName, required this.diff});
  final String fileName;
  final String diff;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      // Effectively full-screen, matching the code panel's max extent.
      initialChildSize: 0.95,
      minChildSize: 0.5,
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
          // Header: file name (monospace) + close.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
            child: Row(
              children: [
                Icon(Icons.difference_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Diff body — vertical scroll (sheet controller) wrapping the
          // shared panel; the panel scrolls horizontally on its own so long
          // lines never wrap or overflow the sheet width.
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              child: UnifiedDiffBody(diff: diff),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable diff body ──────────────────────────────────────────────────────

/// The unified-diff panel itself — a rounded `surfaceContainer` card that
/// scrolls horizontally, rendering the diff line-by-line in monospace with a
/// leading line-number gutter.
///
/// Rendering rules:
///   - gutter      → new-file line number for context/`+` lines, old-file
///                   number for `-` lines, blank for headers (onSurfaceVariant)
///   - `+` lines   → primary-tinted background + 2px primary left edge
///   - `-` lines   → error-tinted background
///   - `@@` hunks  → onSurfaceVariant italic, no number
///   - `+++`/`---` file headers → onSurfaceVariant, no tint, no number
///   - everything else → plain onSurface
class UnifiedDiffBody extends StatelessWidget {
  const UnifiedDiffBody({super.key, required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = _parse(diff);
    final maxNumber = lines.fold<int>(
        0, (max, l) => (l.number ?? 0) > max ? l.number! : max);
    final gutterDigits = maxNumber.toString().length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          // IntrinsicWidth + stretch: every line's tinted background extends
          // to the widest line, not just its own text width.
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in lines)
                  _DiffLine(line: line, gutterDigits: gutterDigits),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Parses the diff, assigning each line a gutter number from the hunk
  /// headers (`@@ -a,b +c,d @@`): context and `+` lines carry the *new*-file
  /// counter, `-` lines the *old*-file counter; headers and anything before
  /// the first hunk get none.
  static List<_ParsedDiffLine> _parse(String diff) {
    final hunkRe = RegExp(r'^@@\s*-(\d+)(?:,\d+)?\s*\+(\d+)(?:,\d+)?\s*@@');
    final out = <_ParsedDiffLine>[];
    int? oldLine; // next '-'/context old-file number
    int? newLine; // next '+'/context new-file number
    for (final line in diff.split('\n')) {
      final hunk = hunkRe.firstMatch(line);
      if (hunk != null) {
        oldLine = int.parse(hunk.group(1)!);
        newLine = int.parse(hunk.group(2)!);
        out.add(_ParsedDiffLine(line, _DiffLineKind.hunk, null));
      } else if (line.startsWith('+++') || line.startsWith('---')) {
        out.add(_ParsedDiffLine(line, _DiffLineKind.meta, null));
      } else if (line.startsWith('+')) {
        out.add(_ParsedDiffLine(line, _DiffLineKind.add, newLine));
        if (newLine != null) newLine++;
      } else if (line.startsWith('-')) {
        out.add(_ParsedDiffLine(line, _DiffLineKind.remove, oldLine));
        if (oldLine != null) oldLine++;
      } else {
        out.add(_ParsedDiffLine(line, _DiffLineKind.context, newLine));
        if (newLine != null) newLine++;
        if (oldLine != null) oldLine++;
      }
    }
    return out;
  }
}

enum _DiffLineKind { add, remove, hunk, meta, context }

class _ParsedDiffLine {
  const _ParsedDiffLine(this.text, this.kind, this.number);
  final String text;
  final _DiffLineKind kind;
  final int? number;
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, required this.gutterDigits});
  final _ParsedDiffLine line;
  final int gutterDigits;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Light palette: the deep-teal primary and red error tint far more
    // faintly over the near-white panel than the bright dark-mode accents
    // do over navy — nudge the alpha up so +/- rows stay visible (still
    // subtle: ~16% over #F5F6F9).
    final tintAlpha =
        Theme.of(context).brightness == Brightness.light ? 0.16 : 0.12;

    Color? background;
    // Transparent (alpha-0 primary — Colors.* is banned) unless added.
    Color edge = cs.primary.withValues(alpha: 0);
    Color textColor = cs.onSurface;
    FontWeight weight = FontWeight.w400;
    FontStyle style = FontStyle.normal;

    switch (line.kind) {
      case _DiffLineKind.hunk:
        textColor = cs.onSurfaceVariant;
        style = FontStyle.italic;
      case _DiffLineKind.meta:
        textColor = cs.onSurfaceVariant;
      case _DiffLineKind.add:
        // ColorScheme has no green/success token; primary (the brand teal)
        // reads green-ish and is the sanctioned stand-in.
        background = cs.primary.withValues(alpha: tintAlpha);
        edge = cs.primary;
        weight = FontWeight.w500; // slight emphasis on additions
      case _DiffLineKind.remove:
        background = cs.error.withValues(alpha: tintAlpha);
      case _DiffLineKind.context:
        break;
    }

    final gutter =
        (line.number?.toString() ?? '').padLeft(gutterDigits);

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(left: BorderSide(width: 2, color: edge)),
      ),
      padding: const EdgeInsets.only(left: 10, right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gutter,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            line.text.isEmpty ? ' ' : line.text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
              color: textColor,
              fontWeight: weight,
              fontStyle: style,
            ),
          ),
        ],
      ),
    );
  }
}
