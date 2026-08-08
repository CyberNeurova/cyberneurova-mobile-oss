import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offers the surface that can actually do what was just typed.
///
/// ## Why it exists
///
/// An ordinary chat has no device tools, and the model is never told so — the
/// context block that would say it is dropped server-side for any section
/// other than `shell`. Asked to write a file, it answers as though it had, and
/// from the user's side an imagined action and a refused one look the same.
/// That is the whole of the owner's original report.
///
/// The model cannot be corrected from here, so the request is caught before it
/// is sent. One tap moves it to Console, where it will actually run.
///
/// ## Why a chip and not a block
///
/// It offers, it does not refuse. Plenty of these messages are perfectly good
/// chat requests — "install ripgrep" might mean "tell me how" — and a chat that
/// argues with you about where your question belongs is worse than one that
/// occasionally suggests something you ignore. So: dismissible, never modal,
/// and it never touches what was typed.
class DeviceSuggestionChip extends StatelessWidget {
  const DeviceSuggestionChip({
    super.key,
    required this.onOpenConsole,
    required this.onDismiss,
  });

  final VoidCallback onOpenConsole;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Icon(Icons.terminal_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  // Says what THIS chat cannot do, in one line, because that
                  // is the fact the user is missing. Not "consider using
                  // Console" — the reason is the useful part.
                  'This chat cannot run anything on your phone. Console can.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: cs.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onOpenConsole();
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Open Console'),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded,
                    size: 16, color: cs.onSurfaceVariant),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
