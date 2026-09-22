import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/last_chat_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Which of the two primary surfaces is currently on screen.
enum AskImagineMode { ask, imagine }

/// Persistent [Ask | Imagine] segmented control, docked in the app-bar title
/// slot on both primary surfaces (reference pattern).
///
/// Why it lives in the header rather than the drawer: switching between
/// chatting and image generation is a *high-frequency* move, and burying it
/// in the sidebar meant two taps plus a mental context switch every time.
/// Promoting it here also lets the drawer drop its "Media" destination, so
/// the sidebar can be reorganised around Projects and Agents instead.
///
/// Navigation uses `go` (replace), not `push`: Ask and Imagine are siblings,
/// so bouncing between them must not grow a back stack.
class AskImagineSwitch extends ConsumerWidget {
  const AskImagineSwitch({super.key, required this.mode});

  final AskImagineMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: isDark ? 0.7 : 0.9),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'Ask',
            selected: mode == AskImagineMode.ask,
            // Return to the CURRENT chat directly — no bootstrap round-trip and
            // no "Opening your chat…" flash.
            onTap: () => goToCurrentChat(context, ref),
          ),
          _Segment(
            label: 'Imagine',
            selected: mode == AskImagineMode.imagine,
            onTap: () => context.goNamed('image-generate'),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          // 36px keeps the pair compact enough for the title slot; the
          // parent AppBar row still gives each segment a ≥44px tap target
          // vertically via its own height.
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Active tab reads as the brand accent (reference design); inactive
            // is transparent.
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
