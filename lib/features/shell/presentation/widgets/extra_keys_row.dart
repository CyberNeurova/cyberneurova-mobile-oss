import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cyberneurova_mobile/core/agent/device/sticky_modifiers.dart';

import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// The keys a phone keyboard doesn't have.
///
/// `docs/shell/08-ROADMAP.md` lists this under **do not cut**: *"Mobile
/// keyboards have no Esc, Ctrl, Tab, arrows, `|`, `/`, `-` or `~`. Users will
/// judge the terminal on this before anything else."*
///
/// Key set and escape sequences follow the teardown of T3 Code's shipping
/// terminal (`docs/shell/09-T3CODE-TEARDOWN.md` §3) rather than being invented
/// here — those sequences are what real shells expect.
///
/// `ctrl` and `alt` are **sticky modifiers**: tap once, arm; the next key is
/// transformed and the modifier disarms. That is the only workable model on a
/// touch screen, where you cannot hold one key while pressing another.
class ExtraKeysRow extends StatefulWidget {
  const ExtraKeysRow({
    super.key,
    required this.onSend,
    required this.modifiers,
    this.onDismiss,
  });

  /// Ctrl/Alt armed for the next keystroke. Owned by the session, not by this
  /// row — see [StickyModifiers] for why that distinction is the whole fix.
  final StickyModifiers modifiers;

  /// Raw bytes to write to the PTY.
  final ValueChanged<String> onSend;

  /// Lets the user reclaim the ~52dp when they don't want it.
  /// Lowers the SOFT KEYBOARD. It used to hide this row instead, which is
  /// what the icon has always promised — so pressing the one control that
  /// looks like "close the keyboard" removed esc/ctrl/tab, with nothing left
  /// on screen to bring them back. Reported by the owner, and correct: a
  /// control that hides itself and offers no way home is a trap.
  final VoidCallback? onDismiss;

  /// Matches T3's accessory height, and clears the 44pt minimum touch target
  /// once the row's vertical padding is included.
  static const double height = 52;

  @override
  State<ExtraKeysRow> createState() => _ExtraKeysRowState();
}

class _ExtraKeysRowState extends State<ExtraKeysRow> {
  /// The armed state lives on the session, NOT here.
  ///
  /// A letter typed on the system keyboard goes straight into the terminal
  /// grid and never passes through this row, so a modifier held locally could
  /// only ever apply to this row's own keys — which is why Ctrl+X could not
  /// be pressed at all. Sharing the state with the write path is the fix.
  StickyModifiers get _mods => widget.modifiers;
  bool get _ctrl => _mods.ctrl;
  bool get _alt => _mods.alt;

  @override
  void initState() {
    super.initState();
    _mods.addListener(_onMods);
  }

  @override
  void dispose() {
    _mods.removeListener(_onMods);
    super.dispose();
  }

  void _onMods() {
    if (mounted) setState(() {});
  }


  void _send(String data) {
    HapticFeedback.selectionClick();
    // consume() applies whatever is armed and disarms, so this row and the
    // system keyboard go through exactly the same path.
    widget.onSend(_mods.consume(data));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // A hairline at low alpha reads on navy and vanishes on the light page —
    // docs/DESIGN.md §3 calls this out explicitly, so specify it twice.
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      height: ExtraKeysRow.height,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: cs.outline.withValues(alpha: isLight ? 1.0 : 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                _key(cs, 'esc', () => _send('')),
                _modifier(cs, 'ctrl', _ctrl, _mods.toggleCtrl),
                _modifier(cs, 'alt', _alt, _mods.toggleAlt),
                _key(cs, 'tab', () => _send('\t')),
                _key(cs, '↑', () => _send('[A')),
                _key(cs, '↓', () => _send('[B')),
                _key(cs, '←', () => _send('[D')),
                _key(cs, '→', () => _send('[C')),
                _key(cs, '~', () => _send('~')),
                _key(cs, '|', () => _send('|')),
                _key(cs, '/', () => _send('/')),
                _key(cs, '-', () => _send('-')),
              ],
            ),
          ),
          if (widget.onDismiss != null)
            IconButton(
              // 44pt minimum — DESIGN.md §3 and Apple HIG.
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Hide keyboard',
              icon: Icon(Icons.keyboard_hide_rounded,
                  size: 20, color: cs.onSurfaceVariant),
              onPressed: widget.onDismiss,
            ),
        ],
      ),
    );
  }

  Widget _key(ColorScheme cs, String label, VoidCallback onTap) => _KeyCap(
        label: label,
        onTap: onTap,
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurface,
        border: cs.outline,
      );

  Widget _modifier(
          ColorScheme cs, String label, bool active, VoidCallback onTap) =>
      _KeyCap(
        label: label,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        // Armed state must be obvious — a sticky modifier the user can't see
        // is worse than no modifier at all.
        background: active ? cs.primary : cs.surfaceContainerHighest,
        foreground: active ? cs.onPrimary : cs.onSurface,
        border: active ? cs.primary : cs.outline,
        semanticsSelected: active,
      );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.border,
    this.semanticsSelected,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color border;
  final bool? semanticsSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: semanticsSelected,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
            onTap: onTap,
            child: Container(
              // 44 wide is too fat for a key row; 40 with 6px gaps still clears
              // the 8px-spacing rule and the row's full height is the target.
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                border: Border.all(color: border),
              ),
              child: Text(
                label,
                style: AppTheme.mono(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
