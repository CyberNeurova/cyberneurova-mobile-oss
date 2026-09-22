import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/model_info.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/model_provider.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/payment_repository.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/local_llm_provider.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';

/// Compact chip showing the currently selected model name.
/// Tap → opens [showModelPickerSheet] for the full list (free + locked).
///
/// Reads `selectedModelProvider` for the live value and `modelsProvider` for
/// the human-readable name. Persists choice via SharedPreferences automatically
/// when the user picks a new one.
class ModelPickerChip extends ConsumerWidget {
  const ModelPickerChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The model that will ACTUALLY answer, not the one that was picked.
    //
    // The chip read the selection while the send used effectiveModelProvider,
    // which silently substitutes on the free tier and after a downgrade — so
    // the picker was reporting a choice rather than a fact. Worse, an id that
    // was not in the list at all fell back to the literal name "Tiny Neurova",
    // which is how the owner watched Gemma turn into Tiny Neurova with no
    // explanation. Never invent a name for an unknown id.
    final effectiveId = ref.watch(effectiveModelProvider);
    final substitution = ref.watch(modelSubstitutionProvider);
    final modelsAsync = ref.watch(modelsProvider);

    // A live local route decides where the message actually goes, so it decides
    // what the chip says. Showing the server model while sending to localhost
    // is the picker lying about the one thing it exists to report — and when
    // that endpoint is down, the failure reads as the named model being broken.
    final localRoute = ref.watch(localRouteProvider);

    final selectedName = localRoute != null
        ? shortModelName(localRoute.model)
        : modelsAsync.when(
      data: (m) {
        final all = [...m.models, ...m.locked];
        for (final mi in all) {
          if (mi.id == effectiveId) return shortModelName(mi.name);
        }
        return shortModelName(effectiveId);
      },
      // Not "Loading…". The selected id is local state and is known on the
      // first frame — only the pretty NAME needs the network. Showing the id's
      // short form immediately means the chip is right from the start and
      // never changes under the user; "Loading…" was a placeholder sitting
      // next to the composer on every cold start, which reads as the app not
      // being ready rather than as one label still resolving.
      loading: () =>
          effectiveId.isEmpty ? 'Model' : shortModelName(effectiveId),
      error: (_, __) =>
          effectiveId.isEmpty ? 'Model' : shortModelName(effectiveId),
    );
    final substituted = substitution == ModelSubstitution.freeTier ||
        substitution == ModelSubstitution.lockedForTier;

    // Theme-driven so the pill looks right in light mode too — the
    // AppTheme.* constants here are dark-only.
    final cs = Theme.of(context).colorScheme;
    // Cap the chip's width and ellipsize the name — long model names (e.g.
    // "CyberNeurova Kimi 2.7 Code") otherwise overflow the app-bar Row (the
    // yellow/black "OVERFLOWED BY Npx" stripe in debug; clipped in release).
    //
    // The cap has to scale with the screen, not sit at a fixed 240. In the
    // Console app bar the chip shares the row with a back button, a title
    // and a drawer button; on a 360dp phone a flat 240 left the title about
    // 24dp and "shell-1" collided with the chip. Yielding a share of the
    // width keeps both readable on a narrow device and still lets the chip
    // grow on a tablet.
    final maxChipWidth =
        math.min(240.0, MediaQuery.sizeOf(context).width * 0.44);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxChipWidth),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          // Re-fetch the lineup every time the picker opens, so a model added
          // or retired server-side shows up WITHOUT closing and reopening the
          // app. The sheet keeps showing the last-known list while this refetch
          // is in flight (`skipLoadingOnRefresh`), so there's no loading flash.
          ref.invalidate(modelsProvider);
          showModelPickerSheet(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 12, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  selectedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              // Marks a model that is answering because policy chose it, not
              // because the user did. Small, but the difference between "the
              // agent got worse" and "my plan changed what answers".
              if (substituted) ...[
                const SizedBox(width: 4),
                Icon(Icons.info_outline_rounded,
                    size: 12, color: cs.onSurfaceVariant),
              ],
              const SizedBox(width: 4),
              Icon(Icons.unfold_more_rounded,
                  size: 12, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that lists every model the user can pick.
/// Locked models show an "Upgrade" hint and open the upgrade flow.
Future<void> showModelPickerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // Use the live theme's surface — was hardcoded to dark-only bg.
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ModelPickerSheet(),
  );
}

class _ModelPickerSheet extends ConsumerWidget {
  const _ModelPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(modelsProvider);
    final selectedId = ref.watch(selectedModelProvider);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Choose a model',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                // Manual refresh (the list also refetches on open). While a
                // refetch is in flight WITH a list already shown, the icon
                // becomes a spinner so the user knows it's checking for updates.
                if (modelsAsync.isLoading && modelsAsync.hasValue)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.invalidate(modelsProvider);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.refresh_rounded,
                          size: 20, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            // Says why something other than the pick is answering. The chip
            // shows a marker; this is where the marker is explained, because
            // the sheet is where the user comes to find out.
            if (modelSubstitutionReason(ref.watch(modelSubstitutionProvider))
                case final reason?) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            modelsAsync.when(
              // First load (no cached list yet) → skeleton rows that mirror the
              // real model rows, rather than a lone spinner. A refetch over an
              // existing list skips this (skipLoadingOnRefresh) and updates in
              // place, with the header spinner as the only cue.
              loading: () => const _ModelPickerShimmer(),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      userMessageFor(context, e),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(modelsProvider),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (resp) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in resp.models)
                    _ModelRow(
                      model: m,
                      selected: m.id == selectedId,
                      locked: false,
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        // Picking a model here means "send to this" — so it
                        // has to stop routing to a local endpoint, or the
                        // choice would be silently ignored.
                        await ref.read(localLlmModelProvider.notifier).stop();
                        await ref
                            .read(selectedModelProvider.notifier)
                            .select(m.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  // Locked-models section is hidden entirely on iOS until
                  // IAP ships (Apple 2.1(b) rejection on build 29 flagged
                  // "references to Plans"). Android + web still show it
                  // and route the tap to cyberneurova.ai/pricing.
                  if (resp.locked.isNotEmpty &&
                      PlatformFlags.showUpgradeCta) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'AVAILABLE WITH UPGRADE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final m in resp.locked)
                      _ModelRow(
                        model: m,
                        selected: false,
                        locked: true,
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          // Apple 3.1.1: on iOS, route to the in-app
                          // Plans screen (StoreKit) instead of the web
                          // checkout — the web page would be a policy
                          // violation.
                          if (PlatformFlags.isIOS) {
                            Navigator.of(context).pop();
                            context.pushNamed('billing-plans');
                          } else {
                            await ref
                                .read(paymentRepositoryProvider)
                                .openUpgrade();
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder for the first model-list load — four rows shaped like
/// [_ModelRow] (avatar + name + description) so the sheet doesn't jump when the
/// real list arrives.
class _ModelPickerShimmer extends StatelessWidget {
  const _ModelPickerShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        4,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 3 ? 8 : 0),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CnShimmer(width: 36, height: 36, radius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CnShimmer(width: 130, height: 13, radius: 6),
                      SizedBox(height: 7),
                      CnShimmer(width: 210, height: 10, radius: 5),
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

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final ModelInfo model;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: locked
                    ? null
                    : LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.8),
                          cs.secondary.withValues(alpha: 0.8),
                        ],
                      ),
                color: locked ? cs.surfaceContainer : null,
                borderRadius: BorderRadius.circular(10),
                border: locked ? Border.all(color: cs.outline) : null,
              ),
              alignment: Alignment.center,
              child: Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.auto_awesome_rounded,
                size: 18,
                // White on the teal→violet brand-gradient avatar reads in
                // both themes (light mode uses the deeper AA-safe accents).
                color: locked ? cs.onSurfaceVariant : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    model.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: locked ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                  if (model.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      model.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (selected)
              Icon(Icons.check_circle_rounded, color: cs.primary, size: 20)
            else if (locked)
              Text(
                PlatformFlags.showUpgradeCta ? 'Upgrade' : 'Premium',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Drops the brand prefix so the chip shows the part that varies.
///
/// Every model is named "CyberNeurova <something>", and the chip is narrow
/// enough to ellipsize in both places it appears — so keeping the prefix
/// means the visible half is the half identical across all of them, and it
/// renders as "CyberNeurova…". The discriminator is the whole reason the
/// chip exists. Names without the prefix are left alone.
@visibleForTesting
String shortModelName(String name) {
  const prefix = 'CyberNeurova ';
  if (name.length > prefix.length && name.startsWith(prefix)) {
    return name.substring(prefix.length);
  }
  return name;
}
