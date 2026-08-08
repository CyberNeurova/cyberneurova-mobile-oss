import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/prompts/presentation/providers/prompts_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Empty-state for a chat that has no messages yet. Shows a time-aware
/// greeting, the "How can I help you today?" subtitle, and a small set of
/// suggested prompts (user's saved Custom Prompts, falling back to defaults).
/// Tapping a prompt drops its text into the input bar.
class WelcomeHint extends ConsumerWidget {
  const WelcomeHint({super.key, required this.onPromptTap});
  final void Function(String) onPromptTap;

  String _greeting(AppL10n l, String? name) {
    final h = DateTime.now().hour;
    final period = h < 12
        ? l.greetingMorning
        : (h < 18 ? l.greetingAfternoon : l.greetingEvening);
    // No name: greet without one, rather than addressing them as "there".
    // "Good morning, there" reads like a form letter whose merge field did
    // not fill, and plenty of accounts genuinely have no name — signing in
    // with a provider that returns only an email is the common case.
    // The period strings stand alone in every locale, so this needs no new
    // translation.
    final who = firstName(name);
    return who == null ? period : l.greetingWithName(period, who);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);
    final user = ref.watch(authProvider).valueOrNull;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 36, color: cs.primary)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    begin: 1.0,
                    end: 1.08,
                    duration: 2400.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: 16),
            Text(
              _greeting(l, user?.name),
              textAlign: TextAlign.center,
              // serifDisplay defaults its color to the dark-mode white —
              // pass cs.onSurface so the welcome heading is visible in
              // light mode.
              style: AppTheme.serifDisplay(
                size: 33,
                weight: FontWeight.w400,
                color: cs.onSurface,
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(
                begin: 0.12, end: 0, duration: 400.ms, curve: Curves.easeOut),
            const SizedBox(height: 8),
            Text(
              l.howCanIHelp,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 15,
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
            const SizedBox(height: 28),
            _SuggestedPromptsInline(onPromptTap: onPromptTap),
          ],
        ),
      ),
    );
  }
}

class _SuggestedPromptsInline extends ConsumerWidget {
  const _SuggestedPromptsInline({required this.onPromptTap});
  final void Function(String) onPromptTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompts = ref.watch(promptsProvider);
    final l = AppL10n.of(context);

    return prompts.maybeWhen(
      data: (list) {
        // Up to 3 of the user's saved prompts. If none, show generic defaults.
        final picks = list.take(3).toList();
        final chips = picks.isEmpty
            ? <_PromptChipInline>[
                _PromptChipInline(
                  icon: Icons.lightbulb_outline_rounded,
                  label: l.promptBrainstorm,
                  onTap: () => onPromptTap(l.promptBrainstorm),
                ),
                _PromptChipInline(
                  icon: Icons.school_outlined,
                  label: l.promptExplain,
                  onTap: () => onPromptTap(l.promptExplain),
                ),
                _PromptChipInline(
                  icon: Icons.code_rounded,
                  label: l.promptCode,
                  onTap: () => onPromptTap(l.promptCode),
                ),
              ]
            : [
                for (final p in picks)
                  _PromptChipInline(
                    icon: Icons.tune_rounded,
                    label: p.title.isEmpty ? p.content : p.title,
                    onTap: () => onPromptTap(p.content),
                  ),
              ];
        // Staggered fade+rise entrance (70ms apart) so the prompts arrive with
        // rhythm instead of snapping in all at once.
        return Column(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              chips[i]
                  .animate()
                  .fadeIn(delay: (i * 70).ms, duration: 320.ms)
                  .slideY(
                      begin: 0.18,
                      end: 0,
                      delay: (i * 70).ms,
                      duration: 320.ms,
                      curve: Curves.easeOutCubic),
              if (i < chips.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PromptChipInline extends StatelessWidget {
  const _PromptChipInline({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        // The chip has no fill — the border is its only affordance. At 0.35
        // alpha the light outline disappears into the light page, so use the
        // full outline there; dark keeps the subtle hairline.
        side: BorderSide(
          color: cs.outline.withValues(
              alpha: Theme.of(context).brightness == Brightness.light
                  ? 1.0
                  : 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name to greet someone by, or null if there isn't one.
///
/// Split on a run of whitespace after trimming: the old
/// `name.split(' ').first` returned an empty string for a name with a
/// leading space, which rendered "Good morning," with a dangling comma —
/// and an account whose name is set to blank is not rare.
@visibleForTesting
String? firstName(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).first;
}
