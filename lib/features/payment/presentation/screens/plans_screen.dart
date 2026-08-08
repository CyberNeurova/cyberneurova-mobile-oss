import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/billing_models.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/iap_models.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/payment_repository.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/providers/billing_provider.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/providers/iap_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Plans screen — the one purchase surface (paywall sheet nudges here,
/// settings' Billing row lands here).
///
/// Monthly plans only (yearly store products don't exist — the backend API §9).
/// Per tier the screen prefers the STORE path: localized store price +
/// StoreKit/Play purchase flow verified server-side. When the store is
/// unavailable (emulator, Play products not yet created, desktop) it
/// degrades to the existing web pricing + web-checkout flow — current
/// users lose nothing.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansProvider);
    final availabilityAsync = ref.watch(iapAvailabilityProvider);
    final statusAsync = ref.watch(iapStatusProvider);
    final purchase = ref.watch(iapPurchaseControllerProvider);

    // Purchase pipeline outcomes surface here (success sheet / error snack),
    // wherever the purchase was started from.
    ref.listen<IapPurchaseState>(iapPurchaseControllerProvider, (prev, next) {
      if (prev?.phase == next.phase) return;
      switch (next.phase) {
        case IapPurchasePhase.success:
          HapticFeedback.mediumImpact();
          _showPostPurchaseSheet(context, ref, next);
        case IapPurchasePhase.failed:
          final failure = next.failure;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure?.message ??
                  'Purchase didn\'t complete. Try again.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Back to idle so the CTA is tappable again (the transaction is
          // safe: unfinished purchases are redelivered by the store).
          ref.read(iapPurchaseControllerProvider.notifier).acknowledge();
        default:
          break;
      }
    });

    // Availability resolves fast (a local store round-trip); waiting for it
    // avoids a web-price → store-price flash. Skeleton until BOTH are in —
    // never an empty flash (the backend API §8).
    final loading = plansAsync.isLoading || availabilityAsync.isLoading;
    final availability =
        availabilityAsync.valueOrNull ?? const IapAvailability.unavailable();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Plans'),
        actions: [
          TextButton(
            onPressed: () => context.pushNamed('billing-history'),
            child: const Text('History'),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: loading
            ? const _PlansShimmer()
            : plansAsync.when(
                loading: () => const _PlansShimmer(),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(plansProvider.future),
                ),
                data: (plans) => _PlansList(
                  plans: plans,
                  availability: availability,
                  statusAsync: statusAsync,
                  purchase: purchase,
                ),
              ),
      ),
    );
  }

  void _showPostPurchaseSheet(
      BuildContext context, WidgetRef ref, IapPurchaseState state) {
    final result = state.result;
    if (result == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (_) => _PostPurchaseSheet(
        result: result,
        tappedTier: state.tier,
        restored: state.restored,
      ),
    ).whenComplete(
        () => ref.read(iapPurchaseControllerProvider.notifier).acknowledge());
  }
}

// ─── Source labels (shared helpers) ──────────────────────────────────────────

String _sourceLabel(String source) => switch (source) {
      'apple' => 'via App Store',
      'google' => 'via Google Play',
      'card' => 'via card',
      'crypto' || 'cryptomus' => 'via crypto',
      _ => source.isEmpty ? '' : 'via $source',
    };

IconData _sourceIcon(String source) => switch (source) {
      'apple' => Icons.apple,
      'google' => Icons.shop_rounded,
      'card' => Icons.credit_card_rounded,
      'crypto' || 'cryptomus' => Icons.currency_bitcoin_rounded,
      _ => Icons.workspace_premium_rounded,
    };

String _formatDate(DateTime d) => DateFormat('MMM d, yyyy').format(d.toLocal());

// ─── Content list ────────────────────────────────────────────────────────────

class _PlansList extends ConsumerWidget {
  const _PlansList({
    required this.plans,
    required this.availability,
    required this.statusAsync,
    required this.purchase,
  });

  final PlansResponse plans;
  final IapAvailability availability;
  final AsyncValue<IapStatus?> statusAsync;
  final IapPurchaseState purchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = statusAsync.valueOrNull;
    // Effective current tier: /iap/status is the richest source (covers all
    // payment sources); the web plans' isCurrentPlan flag is the fallback.
    String? currentTier = status?.tier;
    if (currentTier == null) {
      for (final p in plans.monthly) {
        if (p.isCurrentPlan) {
          currentTier = p.tier;
          break;
        }
      }
    }

    final children = <Widget>[
      // Current plan — tier + which SOURCE backs it (the backend API §1/§5).
      if (statusAsync.isLoading)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: CnShimmer(width: double.infinity, height: 96, radius: 18),
        )
      else if (status != null && status.hasPaidSubscription)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _CurrentPlanCard(status: status),
        ),

      // Monthly plan cards (yearly deliberately not built — §9).
      for (final (i, plan) in plans.monthly.indexed)
        _PlanCard(
          plan: plan,
          isCurrent: currentTier != null
              ? plan.tier == currentTier
              : plan.isCurrentPlan,
          storeProduct: availability.productFor(plan.tier),
          paymentMethods: plans.paymentMethods,
          purchase: purchase,
        )
            .animate(delay: Duration(milliseconds: i * 60))
            .fadeIn(duration: 250.ms, curve: Curves.easeOutCubic)
            .slideY(
                begin: 0.1,
                end: 0,
                duration: 250.ms,
                curve: Curves.easeOutCubic),

      // Apple requires Restore Purchases wherever a paywall lives (§6).
      if (availability.available)
        Center(
          child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () async {
              HapticFeedback.lightImpact();
              try {
                await ref
                    .read(iapPurchaseControllerProvider.notifier)
                    .restore();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Checking the store for your purchases…'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
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
            },
            child: const Text('Restore purchases'),
          ),
        ),

      // Apple guideline 3.1.2(c): auto-renewable subscriptions must display
      // the renewal disclosure + functional Terms of Use (EULA) and Privacy
      // Policy links on the purchase surface.
      const _LegalFooter(),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: children,
    );
  }
}

// ─── Current plan card ───────────────────────────────────────────────────────

class _CurrentPlanCard extends StatefulWidget {
  const _CurrentPlanCard({required this.status});
  final IapStatus status;

  @override
  State<_CurrentPlanCard> createState() => _CurrentPlanCardState();
}

class _CurrentPlanCardState extends State<_CurrentPlanCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = widget.status;
    final multiSource = status.sources.length > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CURRENT PLAN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (status.source.isNotEmpty)
                _SourceChip(source: status.source),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            IapCatalog.displayName(status.tier),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              height: 1.15,
            ),
          ),
          if (status.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Renews or expires ${_formatDate(status.expiresAt!)}',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],

          // Multiple active sources (web + store can coexist, §1/§9) — a
          // deliberate management surface, not an afterthought.
          if (multiSource) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Text(
                      'All subscriptions (${status.sources.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: Icon(Icons.expand_more_rounded,
                          size: 18, color: cs.primary),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      children: [
                        for (final s in status.sources)
                          _SourceRow(source: s),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_sourceIcon(source), size: 14, color: cs.primary),
          const SizedBox(width: 5),
          Text(
            _sourceLabel(source),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final IapSubscriptionSource source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Icon(_sourceIcon(source.source),
              size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${IapCatalog.displayName(source.tier)} · ${_sourceLabel(source.source)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (source.expiresAt != null)
                  Text(
                    'Until ${_formatDate(source.expiresAt!)}',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (source.active)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Plan card ───────────────────────────────────────────────────────────────

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.storeProduct,
    required this.paymentMethods,
    required this.purchase,
  });

  final Plan plan;
  final bool isCurrent;

  /// Non-null when the store can sell this tier → store price + store flow.
  /// Null → web price + web-checkout fallback (unchanged current behavior).
  final IapProduct? storeProduct;
  final List<String> paymentMethods;
  final IapPurchaseState purchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isFree = plan.tier == 'free';
    final highlighted = !isCurrent && plan.canPurchase && !isFree;

    // Store-localized price when available; web price otherwise. Never both,
    // never hardcoded USD next to a store price (the backend API §8).
    final priceText = storeProduct?.price ??
        (isFree ? '\$0' : '\$${plan.price.toStringAsFixed(0)}');

    final busyOnThis = purchase.isBusy && purchase.tier == plan.tier;
    final busyElsewhere = purchase.isBusy && purchase.tier != plan.tier;
    final pendingOnThis =
        busyOnThis && purchase.phase == IapPurchasePhase.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted
            ? cs.primary.withValues(alpha: 0.08)
            : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: highlighted ? cs.primary : cs.outline,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + current-plan badge
          Row(
            children: [
              Text(
                plan.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  child: Text(
                    'CURRENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: cs.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Price — one string, correctly localized for its source.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  priceText,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (!isFree)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '/ month',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Features
          for (final f in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (plan.canPurchase && !isCurrent && !isFree) ...[
            const SizedBox(height: 16),
            if (pendingOnThis)
              const _PendingPill()
            else
              CnButton(
                label: 'Choose ${plan.name}',
                loading: busyOnThis,
                onPressed: busyElsewhere
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        final product = storeProduct;
                        // The App Store payment rule lives in purchaseRouteFor,
                        // not here — see it for why iOS must never reach web.
                        switch (purchaseRouteFor(
                          hasStoreProduct: product != null,
                          isIOS: PlatformFlags.isIOS,
                        )) {
                          case PurchaseRoute.store:
                            // Outcome arrives on the purchase controller
                            // (verify-then-finish pipeline).
                            ref
                                .read(iapPurchaseControllerProvider.notifier)
                                .purchase(product!);
                          case PurchaseRoute.storeUnavailable:
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'The App Store is temporarily unavailable. Please try again in a moment.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          case PurchaseRoute.web:
                            _openWebPurchaseSheet(context);
                        }
                      },
              ),
          ],
        ],
      ),
    );
  }

  void _openWebPurchaseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (_) => _WebPurchaseSheet(
        plan: plan,
        paymentMethods: paymentMethods,
      ),
    );
  }
}

/// Ask to Buy / deferred payment — explicitly NOT an error (the backend API §8).
/// The purchase completes (or not) whenever the approver acts; the store
/// stream delivers the outcome, possibly on a later app launch.
class _PendingPill extends StatelessWidget {
  const _PendingPill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 18, color: cs.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for approval…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'This purchase needs approval (e.g. Ask to Buy). '
                  'It will activate automatically once approved.',
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Post-purchase confirmation ──────────────────────────────────────────────

/// Reflects the VERIFY RESPONSE (the backend API §8): the granted tier can differ
/// from the tapped one when a higher tier is active from another source.
class _PostPurchaseSheet extends StatelessWidget {
  const _PostPurchaseSheet({
    required this.result,
    required this.tappedTier,
    required this.restored,
  });

  final IapVerifyResult result;
  final String? tappedTier;
  final bool restored;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grantedName = IapCatalog.displayName(result.tier);
    final differs = tappedTier != null && tappedTier != result.tier;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: cs.primary),
            const SizedBox(height: 14),
            Text(
              restored
                  ? 'Purchases restored — you\'re on $grantedName'
                  : 'You\'re on $grantedName',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (result.source.isNotEmpty) _sourceLabel(result.source),
                if (result.expiresAt != null)
                  'renews ${_formatDate(result.expiresAt!)}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            if (differs) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: cs.outline),
                ),
                child: Text(
                  'You have more than one active subscription — the highest '
                  'plan applies, so $grantedName is in effect right now.',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            CnButton(
              label: 'Done',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Web-checkout fallback sheet (monthly only) ──────────────────────────────

class _WebPurchaseSheet extends ConsumerStatefulWidget {
  const _WebPurchaseSheet({
    required this.plan,
    required this.paymentMethods,
  });

  final Plan plan;
  final List<String> paymentMethods;

  @override
  ConsumerState<_WebPurchaseSheet> createState() => _WebPurchaseSheetState();
}

class _WebPurchaseSheetState extends ConsumerState<_WebPurchaseSheet> {
  bool _opening = false;
  String? _error;

  Future<void> _checkout() async {
    HapticFeedback.lightImpact();
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      // v1.0 routes web upgrades through the checkout at
      // cyberneurova.ai/pricing (in-app browser sheet — Starlink pattern).
      // The in-app invoice flow (createInvoice → checkout webview → poll)
      // stays bypassed until the backend fixes createInvoice server-side.
      Navigator.pop(context);
      final ok = await ref
          .read(paymentRepositoryProvider)
          .openUpgrade(returnTo: widget.plan.tier);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't open the upgrade page. Try again."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(context, e));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final method = ref.watch(paymentMethodProvider);

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
            Text(
              widget.plan.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '\$${widget.plan.price.toStringAsFixed(0)} / month',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 20),

            // Payment method picker
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'PAYMENT METHOD',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final m in widget.paymentMethods)
              _MethodRow(
                method: m,
                selected: method == m,
                onTap: () {
                  ref.read(paymentMethodProvider.notifier).state = m;
                },
              ),

            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 12),
            ],

            CnButton(
              label: 'Continue to checkout',
              loading: _opening,
              onPressed: _checkout,
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.method,
    required this.selected,
    required this.onTap,
  });
  final String method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCrypto = method == 'crypto' || method == 'cryptomus';
    final icon = isCrypto
        ? Icons.currency_bitcoin_rounded
        : Icons.credit_card_rounded;
    final label = isCrypto ? 'Crypto (Cryptomus)' : 'Card';
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

// ─── Legal footer (Apple 3.1.2(c)) ───────────────────────────────────────────

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bodyStyle = TextStyle(
      fontSize: 11,
      color: cs.onSurfaceVariant,
      height: 1.4,
    );
    final linkStyle = TextStyle(
      fontSize: 11,
      color: cs.primary,
      height: 1.4,
      decoration: TextDecoration.underline,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Subscriptions auto-renew monthly at the price shown until '
            'cancelled at least 24 hours before the end of the current '
            'period. Payment is charged to your Apple ID at confirmation of '
            'purchase. Manage or cancel any time in Settings > Apple ID > '
            'Subscriptions.',
            textAlign: TextAlign.center,
            style: bodyStyle,
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _open(AppConstants.termsUrl),
                child: Text('Terms of Use (EULA)', style: linkStyle),
              ),
              Text('  ·  ', style: bodyStyle),
              GestureDetector(
                onTap: () => _open(AppConstants.privacyPolicyUrl),
                child: Text('Privacy Policy', style: linkStyle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Shimmer ─────────────────────────────────────────────────────────────────

class _PlansShimmer extends StatelessWidget {
  const _PlansShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: const [
        // Current-plan card slot
        Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: CnShimmer(width: double.infinity, height: 96, radius: 18),
        ),
        // Plan card slots
        Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: CnShimmer(width: double.infinity, height: 200, radius: 18),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: CnShimmer(width: double.infinity, height: 200, radius: 18),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: CnShimmer(width: double.infinity, height: 200, radius: 18),
        ),
      ],
    );
  }
}
