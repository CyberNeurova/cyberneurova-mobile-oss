import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/fence_info.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/night-owl.dart';
import 'package:flutter_highlight/themes/github.dart';

import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// The highlight theme for the current brightness (night-owl in dark,
/// github in light).
Map<String, TextStyle> codeTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? nightOwlTheme
        : githubTheme;

/// The code surface color: the highlight theme's own root background, so the
/// container we paint matches the highlighted text exactly.
/// The colour the code block's background must be painted.
///
/// Public so every surface that shows code — the chat bubble, the full
/// panel, the file viewer — paints the same one. Three private copies of
/// this were three chances to disagree in dark mode.
Color codeBackground(BuildContext context, ColorScheme cs) =>
    codeTheme(context)['root']?.backgroundColor ?? cs.surfaceContainer;

/// Copy of the highlight theme with the root background made transparent.
/// [HighlightView] paints its root background at the code's *intrinsic*
/// width, which inside a horizontal scroll view renders as a second,
/// narrower layer (hanging column with short lines, empty gutters when
/// scrolled). We paint the background once on the outer container instead
/// and let the glyphs render on transparency.
Map<String, TextStyle> flatCodeTheme(BuildContext context) {
  final copy = Map<String, TextStyle>.of(codeTheme(context));
  copy['root'] = (copy['root'] ?? const TextStyle())
      .copyWith(backgroundColor: Colors.transparent);
  return copy;
}

/// Accent color for small (11–13px) text on light surfaces. The light
/// palette's primary (#0E9C86) is only ~2.8:1 there — deepen it with
/// onSurface ink to clear 4.5:1. Dark mode returns [cs.primary] untouched
/// (the bright teal is already high-contrast on navy).
Color _accentInk(BuildContext context, ColorScheme cs) =>
    Theme.of(context).brightness == Brightness.light
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.35), cs.primary)
        : cs.primary;

/// Show a code block in a bottom sheet with full scrolling, syntax highlighting,
/// language label, line count, and copy/share actions.
Future<void> showCodePanel(
  BuildContext context, {
  required String code,
  String? language,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CodePanel(code: code, language: language),
  );
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({required this.code, this.language});
  final String code;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lineCount = '\n'.allMatches(code).length + 1;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle
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
          // Header: language · line count · copy · close
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    language ?? 'text',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _accentInk(context, cs),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _sizeLabel(code, lineCount),
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // ONE flat code surface: the rounded container fills the sheet
          // (full width minus 16px margins, full remaining height) and is
          // the only thing painting the code background. Both scroll views
          // live *inside* it, and a ConstrainedBox pins the code to at
          // least the viewport width, so short lines stretch edge to edge
          // and horizontal scrolling never exposes gutters.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: codeBackground(context, cs),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.6),
                    width: 0.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics()),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: HighlightView(
                          code,
                          language: _normalizedLang(language),
                          theme: flatCodeTheme(context),
                          padding: const EdgeInsets.all(16),
                          textStyle: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "12 lines" by default; "12 lines · 6.2 KB" past 4KB so the user can
  /// sense scope before scrolling.
  String _sizeLabel(String code, int lineCount) {
    final base = '$lineCount line${lineCount == 1 ? '' : 's'}';
    final bytes = code.codeUnits.length;
    if (bytes < 4096) return base;
    final kb = (bytes / 1024).toStringAsFixed(1);
    return '$base · $kb KB';
  }

  String _normalizedLang(String? l) => normalizeCodeLang(l);
}

/// Maps short / aliased fence languages to the names `flutter_highlight` knows.
String normalizeCodeLang(String? l) {
  if (l == null || l.isEmpty) return 'plaintext';
  final lower = l.toLowerCase();
  return switch (lower) {
    'js' => 'javascript',
    'ts' || 'tsx' => 'typescript',
    'py' => 'python',
    'sh' || 'shell' || 'zsh' => 'bash',
    'yml' => 'yaml',
    'kt' => 'kotlin',
    'rs' => 'rust',
    'rb' => 'ruby',
    'md' => 'markdown',
    _ => lower,
  };
}

/// Inline, syntax-highlighted code block shown directly in the chat bubble.
/// A header strip shows the language + line count with copy / expand actions;
/// the code renders below (horizontally scrollable). Long blocks show a capped
/// preview with a "Show all" that opens the full-screen [showCodePanel].
class CodeTeaser extends StatelessWidget {
  const CodeTeaser({
    super.key,
    required this.code,
    this.language,
    this.filename,
    this.onRun,
    this.onSave,
  });

  final String code;
  final String? language;

  /// What the model called this block, if the fence said (```html:clock.html).
  /// Shown in place of the language, because a name is more use than a type.
  final String? filename;

  /// Set only on a block the app can actually run — today, the HTML of a
  /// runnable web page. Null everywhere else, because a Run button that
  /// cannot run anything is worse than no button.
  final VoidCallback? onRun;

  /// Writes this block to the session's working directory.
  ///
  /// Set only where there is a device session to write into. The model is
  /// meant to call `file_write` and often does not — it prints the file and
  /// calls the job done — and this is what stands between the user and
  /// retyping a page by hand on a phone.
  final void Function(String suggestedName)? onSave;

  static const int _previewLines = 16;

  void _copy(BuildContext context) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = code.split('\n');
    final lineCount = lines.length;
    final isLong = lineCount > _previewLines;
    final shown = isLong ? lines.take(_previewLines).join('\n') : code;
    final lang =
        (language == null || language!.isEmpty) ? 'code' : language!.toUpperCase();
    // A name beats a type: "CLOCK.HTML" tells the user what this block is for,
    // "HTML" only what it is made of.
    final title = (filename != null && filename!.isNotEmpty) ? filename! : lang;
    final suggested = (filename != null && filename!.isNotEmpty)
        ? filename!
        : 'snippet.${extensionForLanguage(language)}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header strip ──
          Container(
            color: cs.surfaceContainer,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.code_rounded,
                    size: 14, color: _accentInk(context, cs)),
                const SizedBox(width: 6),
                // One Expanded label group rather than Flexible + Spacer: two
                // flexible children split the leftover space evenly, which
                // clipped "CLOCK.HTML" to "CL…" on a row that had plenty of
                // room. The label group takes everything the actions leave.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: _accentInk(context, cs),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$lineCount line${lineCount == 1 ? '' : 's'}',
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (onSave != null)
                  _HeaderAction(
                    icon: Icons.save_alt_rounded,
                    tooltip: 'Save to this session',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSave!(suggested);
                    },
                  ),
                // Deliberately a labelled button rather than another glyph in
                // a row of glyphs: this is the one action that DOES something
                // rather than moving text around, and the report behind it was
                // someone not realising they could use what the model built.
                if (onRun != null) ...[
                  _RunAction(onTap: onRun!),
                  const SizedBox(width: 4),
                ],
                _HeaderAction(
                  icon: Icons.content_copy_rounded,
                  tooltip: 'Copy',
                  onTap: () => _copy(context),
                ),
                _HeaderAction(
                  icon: Icons.open_in_full_rounded,
                  tooltip: 'Expand',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    showCodePanel(context, code: code, language: language);
                  },
                ),
              ],
            ),
          ),
          // ── Code (highlighted, horizontally scrollable) ──
          // Background painted here (not by HighlightView) and code pinned
          // to at least the viewport width, so short lines never leave a
          // hanging column and horizontal scrolling never exposes gutters.
          LayoutBuilder(
            builder: (context, constraints) => Container(
              color: codeBackground(context, cs),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: HighlightView(
                    shown,
                    language: normalizeCodeLang(language),
                    theme: flatCodeTheme(context),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    textStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── "Show all" footer for long blocks ──
          if (isLong)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                showCodePanel(context, code: code, language: language);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  border: Border(
                    top: BorderSide(
                        color: cs.outline.withValues(alpha: 0.4), width: 0.5),
                  ),
                ),
                child: Text(
                  'Show all $lineCount lines',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _accentInk(context, cs),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small icon button used in the code-block header strip.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}

/// The labelled Run pill in a code block header.
class _RunAction extends StatelessWidget {
  const _RunAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        // 44px of height via padding + the row's own, so the target clears the
        // touch minimum without making the header strip taller than the glyphs
        // beside it.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, size: 14, color: cs.onPrimary),
              const SizedBox(width: 3),
              Text(
                'Run',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
