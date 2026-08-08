import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/file_browser.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/code_panel.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Reads one file from the session, properly.
///
/// ## Why not just `cat`
///
/// `cat` in a 40-column phone terminal wraps every line, has no line numbers,
/// no colour, and scrolls away. Reading a 200-line source file that way is
/// genuinely hard, and "read the code you just wrote" is the most common thing
/// a user does after asking the agent to write it.
///
/// So: syntax highlighting, line numbers, and horizontal scrolling instead of
/// wrapping — because indentation is information in most of these files, and
/// wrapping destroys it.
///
/// The file is read through [FileBrowser], which shares the shell's containment
/// check. Nothing here can open something `cd` would refuse to reach.
class FileViewerScreen extends StatefulWidget {
  const FileViewerScreen({
    super.key,
    required this.session,
    required this.guestPath,
  });

  final ShellSession session;
  final String guestPath;

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  late FileBrowser _browser;
  FilePreview? _preview;

  /// Off by default: wrapping mangles indented code, which is most of what
  /// gets opened here. Available because a long prose line in a README is the
  /// opposite case.
  bool _wrap = false;

  /// Editing state. Null until the user asks to edit — a viewer that keeps a
  /// live controller for every file it opens pays for editing nobody asked
  /// for.
  TextEditingController? _editor;
  final _undo = UndoHistoryController();
  bool _dirty = false;
  bool _saving = false;

  bool get _editing => _editor != null;

  @override
  void initState() {
    super.initState();
    _browser = FileBrowser(widget.session);
    _preview = _browser.read(widget.guestPath);
  }

  @override
  void dispose() {
    _editor?.dispose();
    _undo.dispose();
    super.dispose();
  }

  /// Inserts an indent at the caret.
  ///
  /// Two spaces, not a tab character: a phone keyboard has no tab key, and the
  /// files that get edited here are mostly ones the agent just wrote, which
  /// means space-indented. Inserting a real tab would mix the two invisibly.
  void _indent() {
    final e = _editor;
    if (e == null) return;
    HapticFeedback.selectionClick();
    final sel = e.selection;
    final at = sel.isValid ? sel.start : e.text.length;
    final end = sel.isValid ? sel.end : e.text.length;
    e.value = TextEditingValue(
      text: e.text.replaceRange(at, end, '  '),
      selection: TextSelection.collapsed(offset: at + 2),
    );
  }

  /// Whether this file can be edited here at all.
  ///
  /// A truncated preview must not be: saving would write back only the part we
  /// read and silently delete the rest. That is the kind of loss a file
  /// manager has no business risking on a phone where this is the only copy.
  bool get _canEdit {
    final p = _preview;
    return p != null && p.ok && !p.truncated;
  }

  void _startEditing() {
    final text = _preview?.text;
    if (text == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _editor = TextEditingController(text: text)
        ..addListener(() {
          final changed = _editor!.text != (_preview?.text ?? '');
          if (changed != _dirty) setState(() => _dirty = changed);
        });
    });
  }

  Future<void> _save() async {
    final editor = _editor;
    if (editor == null || _saving) return;
    setState(() => _saving = true);

    final error = _browser.write(widget.guestPath, editor.text);
    if (!mounted) return;

    if (error != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // Re-read rather than assuming: what is on disk is the truth, and a write
    // that silently normalised something should show up here rather than in a
    // later diff nobody expects.
    setState(() {
      _preview = _browser.read(widget.guestPath);
      _saving = false;
      _dirty = false;
    });
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Leaves edit mode, asking first when there is something to lose.
  Future<bool> _closeEditor() async {
    if (!_dirty) {
      setState(() {
        _editor?.dispose();
        _editor = null;
      });
      return true;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text('$_name has unsaved edits.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return false;
    setState(() {
      _editor?.dispose();
      _editor = null;
      _dirty = false;
    });
    return true;
  }

  String get _name => p.basename(widget.guestPath);

  void _copy() {
    final text = _preview?.text;
    if (text == null || text.isEmpty) return;
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
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
    final preview = _preview;

    return PopScope(
      // Never lose an edit to a back swipe. On a phone this is the only copy.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _closeEditor() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          leading: IconButton(
            tooltip: _editing ? 'Close editor' : 'Back',
            icon: Icon(_editing
                ? Icons.close_rounded
                : Icons.arrow_back_ios_new_rounded),
            onPressed: () async {
              if (_editing) {
                await _closeEditor();
              } else if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16)),
              Text(
                // The tail identifies a deep path; the head is boilerplate.
                shortenPath(_browser.display(widget.guestPath)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTheme.mono(fontSize: 10.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            if (_editing) ...[
              if (_saving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                TextButton(
                  // Disabled until something changed: a Save that does nothing
                  // teaches people to distrust the one that does.
                  onPressed: _dirty ? _save : null,
                  child: const Text('Save'),
                ),
            ] else ...[
              IconButton(
                tooltip: _wrap ? 'Stop wrapping' : 'Wrap lines',
                icon: Icon(_wrap
                    ? Icons.wrap_text_rounded
                    : Icons.format_align_left_rounded),
                onPressed: () => setState(() => _wrap = !_wrap),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: _copy,
              ),
              if (_canEdit)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _startEditing,
                ),
            ],
          ],
        ),
        body: preview == null
            ? const SizedBox.shrink()
            : !preview.ok
                ? _Message(text: preview.error!)
                : preview.text.trim().isEmpty
                    ? const _Message(text: 'This file is empty.')
                    : Column(
                        children: [
                          if (preview.truncated)
                            _TruncatedBanner(preview: preview),
                          Expanded(
                            child: _editing
                                ? _Editor(
                                    controller: _editor!,
                                    undo: _undo,
                                  )
                                : _Body(
                                    text: preview.text,
                                    language: _languageFor(_name),
                                    wrap: _wrap,
                                  ),
                          ),
                          if (_editing)
                            _EditorBar(
                              controller: _editor!,
                              undo: _undo,
                              onIndent: _indent,
                            ),
                        ],
                      ),
      ),
    );
  }

  /// Extension → the name `flutter_highlight` knows.
  ///
  /// Falls back to plaintext rather than guessing: a wrong grammar colours the
  /// file confidently and incorrectly, which is worse than no colour at all.
  static String _languageFor(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext.isEmpty) {
      // Extension-less files that are almost always one thing.
      return switch (name.toLowerCase()) {
        'makefile' => 'makefile',
        'dockerfile' => 'dockerfile',
        'readme' || 'license' || 'changelog' => 'plaintext',
        _ => name.startsWith('.') ? 'bash' : 'plaintext',
      };
    }
    return normalizeCodeLang(ext.substring(1));
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.text,
    required this.language,
    required this.wrap,
  });

  final String text;
  final String language;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = text.split('\n');
    final gutterWidth = 14.0 + '${lines.length}'.length * 8.0;

    // flatCodeTheme, not the raw one: HighlightView paints its root background
    // at the code's INTRINSIC size, so a short file left the rest of the screen
    // a different colour and a long line scrolled out from under it. Paint it
    // once on the container and let the glyphs sit on transparency.
    final code = HighlightView(
      text,
      language: language,
      theme: flatCodeTheme(context),
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 40),
      textStyle: AppTheme.mono(fontSize: 12.5, height: 1.45),
    );

    return Container(
      color: codeBackground(context, cs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The gutter scrolls VERTICALLY with the code and stays put
          // horizontally — otherwise the numbers slide off screen the moment
          // you pan a long line, which is exactly when you want them.
          _Gutter(count: lines.length, width: gutterWidth),
          Expanded(
            child: wrap
                ? SingleChildScrollView(child: code)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth:
                            MediaQuery.of(context).size.width - gutterWidth,
                      ),
                      child: SingleChildScrollView(child: code),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Line numbers, pinned.
///
/// Rendered as one Text rather than a ListView so it shares the code's exact
/// line height — a per-row list drifts out of alignment as soon as the code's
/// height calculation differs by a fraction of a pixel.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.count, required this.width});

  final int count;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: double.infinity,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 10, 8, 40),
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          [for (var i = 1; i <= count; i++) '$i'].join('\n'),
          textAlign: TextAlign.right,
          style: AppTheme.mono(
            fontSize: 12.5,
            height: 1.45,
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _TruncatedBanner extends StatelessWidget {
  const _TruncatedBanner({required this.preview});

  final FilePreview preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mb = (preview.totalBytes / (1024 * 1024)).toStringAsFixed(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: cs.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            // Says what it did rather than pretending the file is this size.
            child: Text(
              'Showing the first '
              '${(FileBrowser.maxPreviewBytes / 1024).round()} KB of $mb MB',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The editing surface.
///
/// Plain monospace on the file's own background, soft-wrapped. Highlighting is
/// deliberately dropped while editing: keeping it means rebuilding a syntax
/// tree on every keystroke, which on a phone shows up as input lag on exactly
/// the file long enough to be worth editing. Reading is where colour earns its
/// cost; typing is where latency does.
///
/// Wrapped rather than horizontally scrolled, unlike the reader. Indentation
/// is information when you are looking at code, but a caret that can leave the
/// viewport sideways is unusable with a thumb.
class _Editor extends StatelessWidget {
  const _Editor({required this.controller, required this.undo});

  final TextEditingController controller;
  final UndoHistoryController undo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: codeBackground(context, cs),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: TextField(
        controller: controller,
        undoController: undo,
        expands: true,
        maxLines: null,
        minLines: null,
        autofocus: true,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        enableSuggestions: false,
        // Top, not centre. `expands: true` centres by default, so a short
        // file floated in the middle of the screen with its first line
        // halfway down — the one thing no editor has ever done.
        textAlignVertical: TextAlignVertical.top,
        style: AppTheme.mono(fontSize: 12.5, color: cs.onSurface),
        cursorColor: cs.primary,
        decoration: const InputDecoration(
          isDense: true,
          filled: false,
          // Every state, not just `border`. The app theme supplies a filled,
          // rounded, focus-highlighted box for form fields, and `border` alone
          // leaves the focused one — so the editor came up looking like a
          // text input on a form rather than a file.
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// The row an editor needs and a phone keyboard does not have.
///
/// Indent, undo, redo, and where you are in the file. A phone keyboard has no
/// tab key and no undo, so without this the two most ordinary editing actions
/// are simply unavailable — which is most of what "it does not look like an
/// editor" means in practice.
///
/// Sits below the text and above the keyboard, where the extra-keys row sits
/// in the terminal, so the two surfaces put their keys in the same place.
class _EditorBar extends StatelessWidget {
  const _EditorBar({
    required this.controller,
    required this.undo,
    required this.onIndent,
  });

  final TextEditingController controller;
  final UndoHistoryController undo;
  final VoidCallback onIndent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          _Key(label: 'tab', onTap: onIndent),
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: undo,
            builder: (context, value, _) => Row(
              children: [
                _Key(
                  icon: Icons.undo_rounded,
                  onTap: value.canUndo ? undo.undo : null,
                ),
                _Key(
                  icon: Icons.redo_rounded,
                  onTap: value.canRedo ? undo.redo : null,
                ),
              ],
            ),
          ),
          const Spacer(),
          // Where you are, which every editor shows and none of them explain.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final upToCaret = value.selection.isValid
                  ? value.text.substring(0, value.selection.baseOffset.clamp(0, value.text.length))
                  : '';
              final line = '\n'.allMatches(upToCaret).length + 1;
              final total = '\n'.allMatches(value.text).length + 1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'ln $line/$total',
                  style: AppTheme.mono(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: enabled ? 1 : 0.4),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          // 44dp minimum — DESIGN.md §3 and Apple HIG.
          child: Container(
            constraints: const BoxConstraints(minWidth: 46, minHeight: 40),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon,
                    size: 17,
                    color: enabled ? cs.onSurface : cs.onSurfaceVariant)
                : Text(
                    label!,
                    style: AppTheme.mono(
                      fontSize: 12.5,
                      color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
