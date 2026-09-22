import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/constants/dev_flags.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/iap_models.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/iap_repository.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/providers/billing_provider.dart';

/// What the store can sell right now. `unavailable` (emulator, Play products
/// not created yet, no store account, desktop) → the UI shows web prices and
/// routes purchases through the existing web checkout.
final iapAvailabilityProvider = FutureProvider<IapAvailability>((ref) {
  return ref.watch(iapRepositoryProvider).loadProducts();
});

/// Effective subscription + per-source breakdown (`/iap/status`). Null when
/// the call fails — status is an enhancement on the Plans screen, never a
/// reason to block or error it.
final iapStatusProvider = FutureProvider<IapStatus?>((ref) async {
  try {
    return await ref.watch(iapRepositoryProvider).getStatus();
  } catch (_) {
    return null;
  }
});

// ─── Purchase state machine ──────────────────────────────────────────────────

/// Phases of one store purchase attempt:
///
///   idle ──purchase()──▶ launching ──store sheet──▶ pending  (Ask to Buy)
///                            │                        │
///                            │                        ▼ (approved later —
///                            ├──────────────────▶ verifying   maybe days)
///                            │                        │
///                            │              ┌─────────┴─────────┐
///                            │              ▼                   ▼
///                            │           success             failed
///                            │        (verify's tier,     (typed IapFailure,
///                            │         purchase finished)  purchase NOT
///                            │                             finished → store
///                            ▼                             redelivers later)
///                       idle (user cancelled the store sheet)
enum IapPurchasePhase { idle, launching, pending, verifying, success, failed }

class IapPurchaseState {
  const IapPurchaseState({
    this.phase = IapPurchasePhase.idle,
    this.tier,
    this.result,
    this.failure,
    this.restored = false,
  });

  final IapPurchasePhase phase;

  /// Tier of the product the flow concerns (the TAPPED tier — [result.tier]
  /// is what was actually granted and can differ, inbox/026 §1).
  final String? tier;

  /// Set on [IapPurchasePhase.success] — the `/iap/verify` response.
  final IapVerifyResult? result;

  /// Set on [IapPurchasePhase.failed].
  final IapFailure? failure;

  /// True when [result] came from a Restore Purchases pass.
  final bool restored;

  bool get isBusy =>
      phase == IapPurchasePhase.launching ||
      phase == IapPurchasePhase.pending ||
      phase == IapPurchasePhase.verifying;
}

final iapPurchaseControllerProvider =
    NotifierProvider<IapPurchaseController, IapPurchaseState>(
        IapPurchaseController.new);

class IapPurchaseController extends Notifier<IapPurchaseState> {
  StreamSubscription<IapPurchaseEvent>? _sub;

  @override
  IapPurchaseState build() {
    _sub?.cancel();
    // Arming [events] also arms the store's purchase-update stream, so
    // unfinished transactions from a previous run (verify failed / app
    // killed mid-purchase) get redelivered and re-verified as soon as the
    // Plans screen (or paywall) first watches this provider.
    _sub = ref.read(iapRepositoryProvider).events.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return const IapPurchaseState();
  }

  /// Kick off the store flow for [product]. Outcome arrives via [_onEvent].
  Future<void> purchase(IapProduct product) async {
    if (state.isBusy) return;
    state = IapPurchaseState(
        phase: IapPurchasePhase.launching, tier: product.tier);
    try {
      final launched = await ref.read(iapRepositoryProvider).buy(
            product,
            accountId: ref.read(authProvider).valueOrNull?.id,
          );
      if (!launched && state.phase == IapPurchasePhase.launching) {
        state = IapPurchaseState(
          phase: IapPurchasePhase.failed,
          tier: product.tier,
          failure: const IapFailure(IapErrorKind.retryable,
              'The store didn\'t open. Try again.'),
        );
      }
    } catch (_) {
      // Same ownership check as the `!launched` branch above, which had it and
      // this did not. The store's event stream can beat buy()'s return, so by
      // the time we land here the purchase may already be pending or
      // verifying. Overwriting that with "the store didn't open" is not just
      // wrong: `failed` is not `isBusy`, so it re-enables the button and the
      // copy tells the user to try again — for a purchase that is genuinely in
      // flight at the store.
      if (state.phase != IapPurchasePhase.launching) return;
      state = IapPurchaseState(
        phase: IapPurchasePhase.failed,
        tier: product.tier,
        failure: const IapFailure(
            IapErrorKind.retryable, 'The store didn\'t open. Try again.'),
      );
    }
  }

  /// Restore Purchases (§6). Restored entitlements re-verify through the
  /// same event pipeline and land as success states with `restored: true`.
  Future<void> restore() =>
      ref.read(iapRepositoryProvider).restorePurchases();

  /// Called by the UI after it has shown the success/failure surface.
  void acknowledge() => state = const IapPurchaseState();

  void _onEvent(IapPurchaseEvent event) {
    final tier = IapCatalog.tierForQueryId(event.productId) ?? state.tier;
    switch (event) {
      case IapPurchasePending():
        state = IapPurchaseState(phase: IapPurchasePhase.pending, tier: tier);
      case IapPurchaseVerifying():
        state =
            IapPurchaseState(phase: IapPurchasePhase.verifying, tier: tier);
      case IapPurchaseVerified(:final result, :final restored):
        state = IapPurchaseState(
          phase: IapPurchasePhase.success,
          tier: tier,
          result: result,
          restored: restored,
        );
        _refreshAfterGrant();
      case IapPurchaseFailed(:final failure):
        state = IapPurchaseState(
          phase: IapPurchasePhase.failed,
          tier: tier,
          failure: failure,
        );
      case IapPurchaseCanceled():
        state = const IapPurchaseState();
    }
  }

  /// A verified purchase changed the user's entitlements — refresh every
  /// surface that renders them.
  void _refreshAfterGrant() {
    ref.invalidate(iapStatusProvider);
    ref.invalidate(plansProvider);
    if (!devAuthBypass) {
      // Tier-gated affordances (model picker, upload, …) read authProvider's
      // user. refreshMe() swaps state without a loading flash.
      unawaited(
          ref.read(authProvider.notifier).refreshMe().catchError((_) {}));
    }
  }
}
