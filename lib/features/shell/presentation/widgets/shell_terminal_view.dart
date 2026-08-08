import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// A real terminal — character grid, colours, cursor addressing.
///
/// This replaces the scrollback-list renderer, which could show command output
/// and nothing else. `vi`, `nano`, `htop` and `less` all draw by positioning a
/// cursor in a grid and repainting cells; with no grid they produced garbage or
/// nothing at all, and `ls --color` / `git diff` came out flat because the SGR
/// codes were stripped as noise. For something that promises a Linux
/// environment, "you cannot open an editor" is the limit that makes it a toy.
///
/// The pane still keeps a [ShellScrollback] alongside this. That is not
/// duplication: the two consumers want opposite things. The grid needs the raw
/// escape stream to render; the model needs it stripped, or it spends context
/// on bytes that mean nothing and can misread cursor moves as output.
class ShellTerminalView extends StatefulWidget {
  const ShellTerminalView({
    super.key,
    required this.terminal,
    this.fontSize = 12.5,
    this.focusNode,
    this.autofocus = false,
  });

  final Terminal terminal;
  final double fontSize;

  /// Owned by the screen so focus can follow what the terminal is doing —
  /// a full-screen program needs raw keys, a shell prompt does not.
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<ShellTerminalView> createState() => _ShellTerminalViewState();
}

class _ShellTerminalViewState extends State<ShellTerminalView> {
  final _controller = TerminalController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  /// The selected text, or null when nothing is selected.
  ///
  /// Long-press already selected a word and drag already extended it — xterm
  /// does that itself. What was missing was anywhere for the selection to go,
  /// which made it a highlight and nothing more.
  String? get _selectedText {
    final range = _controller.selection;
    if (range == null || range.isCollapsed) return null;
    final text = widget.terminal.buffer.getText(range);
    return text.trim().isEmpty ? null : text;
  }

  Future<void> _copy() async {
    final text = _selectedText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    _controller.clearSelection();
    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Pastes into the SHELL, not into a text field.
  ///
  /// Written straight to the PTY so it behaves exactly as typing would — a
  /// paste containing a newline runs, which is what a terminal does and what
  /// someone pasting a command expects.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.terminal.onOutput?.call(text);
    _controller.clearSelection();
  }

  /// Terminal colours track the app theme rather than the package default.
  ///
  /// `TerminalThemes.defaultTheme` is a dark scheme, which on our light theme
  /// renders a black slab in the middle of a pale screen. Only the background,
  /// foreground and cursor need to follow the app — the sixteen ANSI colours
  /// are what programs actually ask for by name and should stay recognisable.
  TerminalTheme _themeFor(ColorScheme cs, bool isDark) {
    const base = TerminalThemes.defaultTheme;
    return TerminalTheme(
      cursor: cs.primary,
      selection: cs.primary.withValues(alpha: 0.3),
      foreground: cs.onSurface,
      background: cs.surface,
      black: base.black,
      red: base.red,
      green: base.green,
      yellow: base.yellow,
      blue: base.blue,
      magenta: base.magenta,
      cyan: base.cyan,
      white: base.white,
      brightBlack: base.brightBlack,
      brightRed: base.brightRed,
      brightGreen: base.brightGreen,
      brightYellow: base.brightYellow,
      brightBlue: base.brightBlue,
      brightMagenta: base.brightMagenta,
      brightCyan: base.brightCyan,
      brightWhite: base.brightWhite,
      searchHitBackground: base.searchHitBackground,
      searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
      searchHitForeground: base.searchHitForeground,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selected = _selectedText;

    return Stack(
      children: [
        _terminal(cs, isDark),
        if (selected != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: _SelectionBar(
                onCopy: _copy,
                onPaste: _paste,
                onClear: _controller.clearSelection,
              ),
            ),
          ),
      ],
    );
  }

  Widget _terminal(ColorScheme cs, bool isDark) {
    return TerminalView(
      widget.terminal,
      controller: _controller,
      theme: _themeFor(cs, isDark),
      textStyle: TerminalStyle(
        fontSize: widget.fontSize,
        // Our bundled JetBrains Mono, so the grid matches the rest of the app
        // and does not fall back to a system font with different metrics.
        fontFamily: AppTheme.fontMono,
        height: 1.2,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      // The grid measures itself and tells the PTY its real size — replacing
      // the old guess from font metrics, which is what made mksh's line editor
      // redraw against a width that did not exist.
      autoResize: true,
      backgroundOpacity: 0,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      cursorType: TerminalCursorType.block,
    );
  }
}

/// Copy / paste / clear for a terminal selection.
///
/// Floats over the grid rather than pushing it: a selection is transient and
/// nothing should reflow because one exists — the text you are looking at must
/// stay exactly where it was when you selected it.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.onCopy,
    required this.onPaste,
    required this.onClear,
  });

  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      elevation: 3,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _action(cs, 'Copy', Icons.copy_rounded, onCopy),
            _action(cs, 'Paste', Icons.content_paste_rounded, onPaste),
            _action(cs, 'Clear', Icons.close_rounded, onClear),
          ],
        ),
      ),
    );
  }

  Widget _action(
          ColorScheme cs, String label, IconData icon, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: cs.onSurface),
        label: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: cs.onSurface),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      );
}
