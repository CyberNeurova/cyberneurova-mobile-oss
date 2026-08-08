import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/features/shell/presentation/widgets/ask_attach_button.dart';
import 'package:flutter/services.dart';

import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/ask_voice_button.dart';

/// Which half of the workspace the input is talking to.
enum ShellInputMode {
  /// Straight to the shell. What you type is what runs.
  run,

  /// To the agent, in plain language. It decides what to run.
  ask,
}

/// The one input, with an explicit mode.
///
/// `00-OVERVIEW.md` §1 — the terminal and the agent share one session, one
/// directory, one scrollback. So they should share one input too: switching to
/// Ask must not feel like leaving the terminal and entering a chat, because
/// you have not left anything. The cwd, the history and the environment are
/// the same on both sides of the toggle.
///
/// The mode is **explicit, never inferred.** Guessing whether `find . -name
/// "*.log"` is a command or a request is a coin flip, and getting it wrong
/// either runs something the user meant as a question or asks a model to
/// interpret something they meant literally. A visible switch costs one tap
/// and removes the whole class of error.
class ShellInputBar extends StatelessWidget {
  const ShellInputBar({
    super.key,
    required this.chatId,
    required this.controller,
    required this.focusNode,
    required this.mode,
    required this.onModeChanged,
    this.askBusy = false,
    this.shellBusy = false,
    required this.onSubmit,
    required this.onFocus,
    this.busy = false,
    this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  /// Which chat's attachments this composer queues into.
  final String chatId;

  final ShellInputMode mode;
  final ValueChanged<ShellInputMode> onModeChanged;

  /// The model is mid-turn. Shown as a dot on Ask when you are in Shell.
  final bool askBusy;

  /// The shell produced output you have not seen. Shown as a dot on Shell
  /// when you are in Ask.
  final bool shellBusy;

  final VoidCallback onSubmit;
  final VoidCallback onFocus;

  /// True while the agent is working — the send affordance becomes Stop.
  final bool busy;
  final VoidCallback? onStop;

  bool get _isAsk => mode == ShellInputMode.ask;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outline.withValues(alpha: isLight ? 1.0 : 0.35),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeToggle(
            mode: mode,
            onChanged: onModeChanged,
            askBusy: askBusy,
            shellBusy: shellBusy,
          ),
          // Shell mode has no text field at all. Typing goes straight to the
          // grid — which always worked — so a second input sitting under it
          // was both redundant and the most expensive thing on screen. On a
          // phone that space is the terminal's to use.
          //
          // Ask keeps its field: there is nothing to type into up there, and a
          // prompt is a paragraph rather than a line.
          if (_isAsk) ...[
            const SizedBox(height: 6),
            // What is queued, above the field. Ask only: Shell types straight
            // into the grid and has nothing to attach a file to.
            AskAttachmentStrip(chatId: chatId),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The prompt glyph doubles as the mode indicator, so the mode is
                // legible from the caret itself without reading the toggle.
                AskAttachButton(chatId: chatId),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 2, right: 8),
                  child: _isAsk
                      ? Icon(Icons.auto_awesome, size: 15, color: cs.primary)
                      : Text(
                          '\$',
                          style: AppTheme.mono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onTap: onFocus,
                    autocorrect: _isAsk,
                    enableSuggestions: _isAsk,
                    // A shell is character-exact; autocapitalise would silently
                    // corrupt commands. Prose wants the opposite.
                    textCapitalization: _isAsk
                        ? TextCapitalization.sentences
                        : TextCapitalization.none,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    // A multi-line field makes the soft keyboard show a newline
                    // key and IGNORE textInputAction, so Enter inserted a break
                    // instead of running — fatal in a shell, where Enter is the
                    // verb. Keep wrapping, treat a typed newline as send.
                    onChanged: (value) {
                      if (value.endsWith('\n')) {
                        controller.text = value.substring(0, value.length - 1);
                        onSubmit();
                      }
                    },
                    maxLines: _isAsk ? 5 : 4,
                    minLines: 1,
                    style: _isAsk
                        ? TextStyle(fontSize: 14.5, color: cs.onSurface)
                        : AppTheme.mono(fontSize: 13.5, color: cs.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      hintText: 'Describe what you want done…',
                      hintStyle:
                          TextStyle(fontSize: 14.5, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                // Dictation, not a second send path: the transcript lands in
                // the field so it can be edited before it goes anywhere. A
                // long instruction is thirty seconds of speech and a minute of
                // thumb-typing, and the phone is the whole computer.
                AskVoiceButton(
                  onTranscribed: (text) {
                    final existing = controller.text.trimRight();
                    controller.text =
                        existing.isEmpty ? text : '$existing $text';
                    controller.selection = TextSelection.collapsed(
                      offset: controller.text.length,
                    );
                  },
                ),
                _SendButton(
                  busy: busy,
                  isAsk: _isAsk,
                  onTap: busy ? (onStop ?? () {}) : onSubmit,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Two segments. Deliberately small and quiet — it is a persistent control
/// that must not compete with the output for attention.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.onChanged,
    this.askBusy = false,
    this.shellBusy = false,
  });

  final ShellInputMode mode;
  final ValueChanged<ShellInputMode> onChanged;

  /// Whether the model is mid-turn.
  final bool askBusy;

  /// Whether the shell has output the user has not seen since leaving it.
  final bool shellBusy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment(cs, ShellInputMode.run, 'Shell', Icons.terminal_rounded,
                busy: shellBusy),
            _segment(cs, ShellInputMode.ask, 'Ask', Icons.auto_awesome,
                busy: askBusy),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    ColorScheme cs,
    ShellInputMode value,
    String label,
    IconData icon, {
    bool busy = false,
  }) {
    final selected = mode == value;
    // Only ever on the tab you are NOT looking at. On the visible one the work
    // is already on screen, and a second indicator for it would be noise.
    final showDot = busy && !selected;
    return Semantics(
      button: true,
      selected: selected,
      label: busy && !selected ? '$label mode, working' : '$label mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          onChanged(value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 5),
              if (showDot) ...[
                // Both sides of one session keep running when you switch, so
                // the only thing missing was knowing that they had. A dot is
                // enough — it answers "is it still going?" without pulling
                // attention off whatever you switched over to do.
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.busy,
    required this.isAsk,
    required this.onTap,
  });

  final bool busy;
  final bool isAsk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: busy ? 'Stop' : (isAsk ? 'Send to agent' : 'Run command'),
      child: IconButton(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(
          busy
              ? Icons.stop_circle_rounded
              : (isAsk
                  ? Icons.arrow_upward_rounded
                  : Icons.keyboard_return_rounded),
          size: 21,
          color: busy ? cs.error : cs.primary,
        ),
        onPressed: onTap,
      ),
    );
  }
}
