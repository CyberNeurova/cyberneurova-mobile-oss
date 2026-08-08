import 'package:cyberneurova_mobile/features/payment/presentation/screens/billing_labels.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/capabilities/data/models/capability_models.dart';
import 'package:cyberneurova_mobile/features/capabilities/presentation/providers/capabilities_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Capabilities = Skills + Tools in one screen. Two sections, same row UI.
/// Tier-gated rows show a "Premium" badge instead of an active Switch and
/// snap the toggle back if the user tries to flip it (snackbar nudge).
class CapabilitiesScreen extends ConsumerWidget {
  const CapabilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillsProvider);
    final tools = ref.watch(toolsProvider);
    final l = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l.capabilities),
      ),
      body: RefreshIndicator(
        color: cs.primary,
        onRefresh: () async {
          ref.invalidate(skillsProvider);
          ref.invalidate(toolsProvider);
          await Future.wait([
            ref.read(skillsProvider.future),
            ref.read(toolsProvider.future),
          ]);
        },
        child: MaxWidthContent(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Skills section
            _Section(
              title: l.skills,
              subtitle:
                  'Reusable system-prompt patterns the AI can apply.',
              child: skills.when(
                loading: () => const _ListShimmer(),
                error: (e, _) => ErrorView(
                  error: e,
                  compact: true,
                  onRetry: () => ref.refresh(skillsProvider.future),
                ),
                data: (list) => list.isEmpty
                    ? const _EmptyHint(label: 'No skills yet')
                    : Column(
                        children: [
                          for (final s in list)
                            _CapabilityRow(
                              capability: s,
                              onToggle: (v) => _onToggle(
                                context: context,
                                ref: ref,
                                cap: s,
                                kind: 'skill',
                                newValue: v,
                              ),
                            ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // Tools section
            _Section(
              title: l.tools,
              subtitle:
                  'Functions the AI can call to interact with the outside world.',
              child: tools.when(
                loading: () => const _ListShimmer(),
                error: (e, _) => ErrorView(
                  error: e,
                  compact: true,
                  onRetry: () => ref.refresh(toolsProvider.future),
                ),
                data: (list) => list.isEmpty
                    ? const _EmptyHint(label: 'No tools yet')
                    : Column(
                        children: [
                          for (final t in list)
                            _CapabilityRow(
                              capability: t,
                              onToggle: (v) => _onToggle(
                                context: context,
                                ref: ref,
                                cap: t,
                                kind: 'tool',
                                newValue: v,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        )),
      ),
    );
  }

  Future<void> _onToggle({
    required BuildContext context,
    required WidgetRef ref,
    required CapabilityModel cap,
    required String kind,
    required bool newValue,
  }) async {
    // Tier gate — snap back + nudge, never let an unauthorised flip reach
    // the server (cleaner UX than a 403 toast).
    if (!cap.accessible) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Upgrade to ${_tierLabel(cap.requiredTier)} to enable this.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    try {
      if (kind == 'skill') {
        await ref.read(skillsProvider.notifier).toggle(cap.id, newValue);
      } else {
        await ref.read(toolsProvider.notifier).toggle(cap.id, newValue);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessageFor(context, e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Was its own switch ending in `_ => 'Free'`. On this screen the badge says
  // which plan a capability NEEDS, so an unknown tier — `starter`, or anything
  // added later — was advertised as available on the free plan. Found by the
  // repo-wide guard test after the same idiom turned up in billing history and
  // the billing result screen.
  String _tierLabel(String t) => tierLabel(t);
}

// ─── Section wrapper ─────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline),
          ),
          child: child,
        ),
      ],
    );
  }
}

// ─── Single row ──────────────────────────────────────────────────────────────

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.capability,
    required this.onToggle,
  });
  final CapabilityModel capability;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cap = capability;
    final locked = !cap.accessible;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Type icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: locked
                  ? cs.onSurfaceVariant.withValues(alpha: 0.15)
                  : cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              cap.type == 'custom'
                  ? Icons.tune_rounded
                  : Icons.extension_outlined,
              size: 16,
              color: locked ? cs.onSurfaceVariant : cs.primary,
            ),
          ),
          const SizedBox(width: 12),

          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        cap.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: locked
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _tierLabel(cap.requiredTier).toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (cap.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    cap.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Switch — visually disabled but still tappable so we can show
          // the nudge snackbar. The notifier ignores the call when locked.
          Switch(
            value: cap.enabled,
            onChanged: onToggle,
            activeThumbColor: cs.primary,
            inactiveTrackColor: cs.outline,
            // The off state had no thumb colour, so it fell back to
            // `onSurfaceVariant` — near enough to `cs.outline` that the track
            // and the thumb were the same grey. Every switch on this screen
            // rendered as a blank pill with nothing in it, so a user could not
            // tell there was a control there at all, let alone which way it
            // was set (device, 2026-08-05).
            inactiveThumbColor: cs.surface,
          ),
        ],
      ),
    );
  }

  // Was its own switch ending in `_ => 'Free'`. On this screen the badge says
  // which plan a capability NEEDS, so an unknown tier — `starter`, or anything
  // added later — was advertised as available on the free plan. Found by the
  // repo-wide guard test after the same idiom turned up in billing history and
  // the billing result screen.
  String _tierLabel(String t) => tierLabel(t);
}

// ─── Shimmer + empty hint ────────────────────────────────────────────────────

class _ListShimmer extends StatelessWidget {
  const _ListShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: List.generate(
          3,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
            child: const Row(
              children: [
                CnShimmer(width: 32, height: 32, radius: 8),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CnShimmer(width: 120, height: 12, radius: 6),
                      SizedBox(height: 6),
                      CnShimmer(width: 200, height: 10, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      ),
    );
  }
}
