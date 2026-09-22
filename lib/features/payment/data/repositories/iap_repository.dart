import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/constants/dev_flags.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/iap_models.dart';

final iapRepositoryProvider = Provider<IapRepository>((ref) {
  final repo = IapRepository(ref.watch(apiClientProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Store IAP layer (inbox/026): StoreKit 2 on iOS (live today), Play Billing
/// on Android (blocked on Play Console — degrades to unavailable until the
/// products exist, at which point this code path lights up unchanged).
///
/// Contract highlights implemented here:
///  * **finish-after-verify** (§3.6/§4.5): a purchase is completed /
///    acknowledged ONLY after `POST /iap/verify` succeeds. On verify failure
///    the transaction stays in the store's unfinished queue and is
///    redelivered on next app start / restore — the JWS/token is never lost.
///  * **effective tier** (§1): the verify response's `tier`/`source` is
///    surfaced as-is; it may differ from the purchased product when a higher
///    tier is active from another source.
///  * **pending ≠ failed** (§8): Ask to Buy / family-approval purchases emit
///    a distinct [IapPurchasePending] event.
///  * **restore is idempotent** (§6): restore re-runs verify for every owned
///    entitlement; the server just re-confirms, nothing double-grants.
class IapRepository {
  IapRepository(this._client, {InAppPurchase? storeClient})
      : _iap = storeClient ?? InAppPurchase.instance;

  final ApiClient _client;
  final InAppPurchase _iap;

  StreamSubscription<List<PurchaseDetails>>? _storeSub;
  final _events = StreamController<IapPurchaseEvent>.broadcast();

  /// Purchase pipeline events. Listening also arms the store purchase-update
  /// subscription so unfinished transactions (e.g. verify failed last run)
  /// get redelivered and re-verified.
  Stream<IapPurchaseEvent> get events {
    _ensureListening();
    return _events.stream;
  }

  void _ensureListening() {
    _storeSub ??= _iap.purchaseStream.listen(_onPurchaseUpdates);
  }

  // ─── Products ──────────────────────────────────────────────────────────────

  /// Ask the store what it can sell. ANY failure — no store, query error,
  /// zero products found (the Android reality until Play Console unlocks) —
  /// collapses to [IapAvailability.unavailable] so the UI falls back to the
  /// existing web-checkout flow with web pricing. Never throws.
  Future<IapAvailability> loadProducts() async {
    if (!PlatformFlags.isMobile) return const IapAvailability.unavailable();
    try {
      _ensureListening();
      if (!await _iap.isAvailable()) {
        return const IapAvailability.unavailable();
      }
      // Android Play Billing only completes purchases for builds Play itself
      // installed and signed. A sideloaded dev APK or a de-Googled ROM can
      // still *query* products, but launching a purchase is refused with
      // "this version of the application is not configured for billing" — a
      // dead end. Treat those as unavailable so the UI uses web checkout
      // (Android's allowed external path) instead of surfacing that error.
      // A Play-installed build reports installer `com.android.vending`.
      if (PlatformFlags.isAndroid && !await _installedFromPlay()) {
        return const IapAvailability.unavailable();
      }
      final queryIds = IapCatalog.storeQueryIds; // tier → store id
      final response =
          await _iap.queryProductDetails(queryIds.values.toSet());
      final products = <IapProduct>[];
      for (final entry in queryIds.entries) {
        // Android explodes a subscription into one ProductDetails per
        // base-plan/offer (same id) — first match is the monthly base plan
        // today since monthly is the only plan that will exist. Revisit if
        // more base plans are ever added in Play Console.
        ProductDetails? details;
        for (final d in response.productDetails) {
          if (d.id == entry.value) {
            details = d;
            break;
          }
        }
        final serverId = IapCatalog.serverProductId(entry.key);
        if (details == null || serverId == null) continue;
        products.add(IapProduct(
          tier: entry.key,
          serverProductId: serverId,
          price: details.price, // localized store string (§8)
          details: details,
        ));
      }
      if (products.isEmpty) return const IapAvailability.unavailable();
      products.sort(
          (a, b) => IapCatalog.rankOf(a.tier).compareTo(IapCatalog.rankOf(b.tier)));
      return IapAvailability.available(products);
    } catch (_) {
      return const IapAvailability.unavailable();
    }
  }

  /// Whether Google Play installed this build — the precondition for Play
  /// Billing actually completing a purchase (as opposed to a sideloaded or
  /// de-Googled install, where product queries succeed but the purchase
  /// launch is refused). Unknown installer is treated as "not Play" so the
  /// UI degrades to web checkout rather than risking the billing dead end.
  Future<bool> _installedFromPlay() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.installerStore == 'com.android.vending';
    } catch (_) {
      return false;
    }
  }

  // ─── Purchase ──────────────────────────────────────────────────────────────

  /// Launch the store purchase sheet. Returns whether the flow opened; the
  /// outcome arrives asynchronously on [events]. [accountId] is forwarded as
  /// `applicationUserName` → StoreKit 2 `appAccountToken` (§3.2), letting
  /// Apple's webhooks carry the user id even if the client's verify call is
  /// lost. (StoreKit 2 only accepts UUID-shaped values; non-UUID ids are
  /// dropped by the plugin — harmless, verify remains the primary link.)
  Future<bool> buy(IapProduct product, {String? accountId}) async {
    _ensureListening();
    final param = PurchaseParam(
      productDetails: product.details,
      applicationUserName: accountId,
    );
    // Subscriptions go through buyNonConsumable in the unified plugin API.
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Re-deliver everything the store says the user owns; each entitlement is
  /// re-verified through the same pipeline (§6 — verify is idempotent).
  /// Results arrive on [events] as [IapPurchaseVerified] with
  /// `restored: true`.
  Future<void> restorePurchases() async {
    _ensureListening();
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // Ask to Buy / deferred payment — distinct state, NOT a failure.
          _events.add(IapPurchasePending(p.productID));

        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(p);
            } catch (_) {/* nothing to recover */}
          }
          _events.add(IapPurchaseCanceled(p.productID));

        case PurchaseStatus.error:
          if (p.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(p);
            } catch (_) {}
          }
          _events.add(IapPurchaseFailed(
            p.productID,
            IapFailure(
              IapErrorKind.retryable,
              p.error?.message.isNotEmpty == true
                  ? 'The store reported a problem. Try again.'
                  : 'Purchase didn\'t complete. Try again.',
              code: p.error?.code,
            ),
          ));

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _events.add(IapPurchaseVerifying(p.productID));
          try {
            final result = await _verifyWithServer(p);
            // Finish-after-verify (§3.6/§4.5): only now is it safe to let
            // the store forget the transaction.
            await _iap.completePurchase(p);
            _events.add(IapPurchaseVerified(
              p.productID,
              result,
              restored: p.status == PurchaseStatus.restored,
            ));
          } catch (e) {
            // Deliberately NOT completed — the store redelivers on next
            // launch/restore, so a network blip can't eat a paid purchase.
            _events.add(IapPurchaseFailed(p.productID, mapVerifyError(e)));
          }
      }
    }
  }

  /// `POST /iap/verify` — the server cross-checks Apple/Google's own servers
  /// and reconciles all sources; the response is the effective result (§1).
  Future<IapVerifyResult> _verifyWithServer(PurchaseDetails p) async {
    final tier = IapCatalog.tierForQueryId(p.productID);
    final serverProductId =
        (tier != null ? IapCatalog.serverProductId(tier) : null) ?? p.productID;
    final token = p.verificationData.serverVerificationData;
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.IAP_VERIFY,
      data: {
        'platform': PlatformFlags.isIOS ? 'ios' : 'android',
        'productId': serverProductId,
        // iOS: the StoreKit 2 signed transaction (JWS). Android: the Play
        // Billing purchase token. Same field on PurchaseDetails, different
        // key on the wire (§3.5/§4.4).
        if (PlatformFlags.isIOS) 'jws': token else 'purchaseToken': token,
      },
    );
    return IapVerifyResult.fromJson(res.data ?? const {});
  }

  /// Map the §3 error table (plus transport-level failures) onto typed
  /// results: retryable vs client bug vs contact-support.
  IapFailure mapVerifyError(Object e) {
    if (e is ApiException && e.statusCode == 400) {
      // The backend puts the machine code in the envelope's `error` field,
      // which ErrorInterceptor surfaces as the message.
      final code = (e.code ?? e.message).toLowerCase();
      if (code.contains('invalid_signature')) {
        return const IapFailure(
          IapErrorKind.support,
          'This purchase couldn\'t be verified. Contact support and we\'ll sort it out.',
          code: 'invalid_signature',
        );
      }
      // product_unknown / product_mismatch — client bookkeeping bug, should
      // never surface in production (§3 table).
      return IapFailure(
        IapErrorKind.bug,
        'Something went wrong on our side. The purchase wasn\'t charged twice — try again later.',
        code: code,
      );
    }
    if (e is UnauthorizedException) {
      return const IapFailure(
        IapErrorKind.retryable,
        'Your session expired. Try again to finish activating the purchase.',
        code: 'unauthorized',
      );
    }
    if (e is ServiceUnavailableException) {
      // 503 iap_not_configured — not user-actionable (§3 table).
      return const IapFailure(
        IapErrorKind.retryable,
        'Purchases are briefly unavailable. Try again shortly.',
        code: 'iap_not_configured',
      );
    }
    if (e is ServerException ||
        e is NetworkException ||
        e is TimeoutException) {
      // 502 api_error (Apple/Google upstream) or plain connectivity.
      return const IapFailure(
        IapErrorKind.retryable,
        'Couldn\'t reach the store to confirm your purchase. It\'s safe — try again.',
        code: 'api_error',
      );
    }
    return const IapFailure(
      IapErrorKind.retryable,
      'Purchase verification didn\'t complete. Try again.',
    );
  }

  // ─── Status ────────────────────────────────────────────────────────────────

  /// `GET /iap/status` — effective tier + every contributing source (§5).
  ///
  /// Dev sandbox: with [devAuthBypass] returns a canned multi-source status
  /// (pro via Apple + premium via card) with NO network, so the Plans
  /// screen's current-plan/multi-source UI is drivable on an emulator —
  /// same pattern as [DevMockChatRepository].
  Future<IapStatus> getStatus() async {
    if (devAuthBypass) {
      final now = DateTime.now();
      return IapStatus(
        tier: 'pro',
        source: 'apple',
        expiresAt: now.add(const Duration(days: 30)),
        sources: [
          IapSubscriptionSource(
            source: 'apple',
            tier: 'pro',
            active: true,
            expiresAt: now.add(const Duration(days: 30)),
          ),
          IapSubscriptionSource(
            source: 'card',
            tier: 'premium',
            active: true,
            expiresAt: now.add(const Duration(days: 16)),
          ),
        ],
      );
    }
    final res =
        await _client.get<Map<String, dynamic>>(ApiConstants.IAP_STATUS);
    return IapStatus.fromJson(res.data ?? const {});
  }

  void dispose() {
    _storeSub?.cancel();
    _events.close();
  }
}
