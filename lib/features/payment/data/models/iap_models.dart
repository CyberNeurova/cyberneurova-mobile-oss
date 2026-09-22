import 'package:in_app_purchase/in_app_purchase.dart' show ProductDetails;
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';

/// Store-product catalog + tier ranking, in ONE place (inbox/026 §3/§4).
///
/// The strings are load-bearing: a typo means "product not found" on-device
/// (iOS) or `product_unknown` from `/iap/verify`. Change them only in
/// lockstep with App Store Connect / Play Console / the server's accepted
/// list.
class IapCatalog {
  IapCatalog._();

  /// Rank used by the server's reconciliation (highest active tier wins).
  /// Mirrored client-side only for sorting/display — the server's
  /// `/iap/verify` response stays the source of truth for what was granted.
  static const Map<String, int> tierRank = {
    'free': 0,
    'starter': 1,
    'premium': 2,
    'pro': 3,
    'pro_max': 4,
  };

  /// iOS App Store product IDs (live in App Store Connect — inbox/026 §3.1).
  /// Monthly only: yearly variants are accepted by the server for
  /// forward-compat but do NOT exist as real products yet (§9).
  static const Map<String, String> iosProductIds = {
    'starter': 'cn_starter_monthly_v1',
    'premium': 'cn_premium_monthly_v1',
    'pro': 'cn_pro_monthly_v1',
    'pro_max': 'cn_pro_max_monthly_v1',
  };

  /// Android: the store is queried by *subscription id*; the server's
  /// `/iap/verify` wants `<subscriptionId>:<basePlanId>` (§4). None of these
  /// exist in Play Console yet (closed-testing gate) — loadProducts()
  /// naturally degrades to unavailable until they're created, at which point
  /// these strings must be updated to match the real console entries.
  static const Map<String, String> androidSubscriptionIds = {
    'starter': 'starter',
    'premium': 'premium',
    'pro': 'pro',
    'pro_max': 'pro_max',
  };

  /// `<subscriptionId>:<basePlanId>` sent to `/iap/verify` (§4).
  /// Note: Play base-plan ids can't contain underscores, hence
  /// `pro-max-monthly` for the pro_max subscription.
  static const Map<String, String> androidServerProductIds = {
    'starter': 'starter:starter-monthly',
    'premium': 'premium:premium-monthly',
    'pro': 'pro:pro-monthly',
    'pro_max': 'pro_max:pro-max-monthly',
  };

  /// tier → id used with `queryProductDetails` on the current platform.
  static Map<String, String> get storeQueryIds =>
      PlatformFlags.isIOS ? iosProductIds : androidSubscriptionIds;

  /// The `productId` string `/iap/verify` expects for [tier].
  static String? serverProductId(String tier) => PlatformFlags.isIOS
      ? iosProductIds[tier]
      : androidServerProductIds[tier];

  /// Reverse lookup: store query id (what `PurchaseDetails.productID`
  /// carries) → tier.
  static String? tierForQueryId(String id) {
    for (final e in storeQueryIds.entries) {
      if (e.value == id) return e.key;
    }
    return null;
  }

  static int rankOf(String tier) => tierRank[tier] ?? 0;

  static String displayName(String tier) => switch (tier) {
        'free' => 'Free',
        'starter' => 'Starter',
        'premium' => 'Premium',
        'pro' => 'Pro',
        'pro_max' => 'Pro Max',
        _ => tier,
      };
}

// ─── Products / availability ─────────────────────────────────────────────────

/// One purchasable store product, resolved against [IapCatalog].
class IapProduct {
  const IapProduct({
    required this.tier,
    required this.serverProductId,
    required this.price,
    required this.details,
  });

  final String tier;

  /// What `/iap/verify` expects as `productId` (differs from the store query
  /// id on Android — `<sub>:<basePlan>` vs bare subscription id).
  final String serverProductId;

  /// Localized, store-formatted price string ("US$9.99", "₹799", …). Always
  /// display THIS next to a store CTA — never a hardcoded USD amount
  /// (inbox/026 §8).
  final String price;

  /// Live handle needed to launch the store purchase flow.
  final ProductDetails details;
}

/// Result of asking the store what it can sell right now. `unavailable`
/// covers everything from "no Play services" to "products not created yet"
/// — the UI then falls back to the web-checkout flow with web pricing.
class IapAvailability {
  const IapAvailability.unavailable()
      : available = false,
        products = const [];
  const IapAvailability.available(this.products) : available = true;

  final bool available;
  final List<IapProduct> products; // sorted by tier rank, ascending

  IapProduct? productFor(String tier) {
    for (final p in products) {
      if (p.tier == tier) return p;
    }
    return null;
  }
}

// ─── Where a purchase tap goes ───────────────────────────────────────────────

/// The three ends a "Choose plan" tap can reach.
enum PurchaseRoute {
  /// The store has a real product in hand — launch StoreKit / Play billing.
  store,

  /// The store should sell this but has nothing to offer right now: not
  /// configured yet, an outage, or products still un-created. On iOS an
  /// unavailable store ends HERE, shown as a try-again, and never falls
  /// through to [web].
  storeUnavailable,

  /// Web checkout. Reachable only where an external payment path is allowed —
  /// Android, never iOS.
  web,
}

/// Decides where a subscription purchase should go, in one place instead of an
/// `else if` buried in a button callback.
///
/// This is the App Store rule made explicit and testable. Apple 3.1.1:
/// subscriptions are StoreKit-only, and offering an external web checkout for
/// them is a rejection — this app has taken two already (build 29 and build 35,
/// both 2.1(b)). So the load-bearing line is the middle one: with no store
/// product, iOS must resolve to [storeUnavailable], not [web]. Everything about
/// showing billing on iOS at all rides on that never regressing.
///
/// Pure and platform-passed rather than reading [PlatformFlags] inside, because
/// the host running the tests is neither iOS nor Android — the only way to
/// assert the iOS branch off-device is to hand it `isIOS: true`.
PurchaseRoute purchaseRouteFor({
  required bool hasStoreProduct,
  required bool isIOS,
}) {
  if (hasStoreProduct) return PurchaseRoute.store;
  if (isIOS) return PurchaseRoute.storeUnavailable;
  return PurchaseRoute.web;
}

// ─── Verify / status ─────────────────────────────────────────────────────────

/// `/iap/verify` 200 response. `tier`/`source` reflect the user's EFFECTIVE
/// subscription after reconciliation — which can differ from the product
/// just purchased if a higher tier is active elsewhere (inbox/026 §1, §3.5).
class IapVerifyResult {
  const IapVerifyResult({
    required this.tier,
    required this.source,
    this.expiresAt,
  });

  factory IapVerifyResult.fromJson(Map<String, dynamic> json) {
    return IapVerifyResult(
      tier: json['tier'] is String ? json['tier'] as String : 'free',
      source: json['source'] is String ? json['source'] as String : '',
      expiresAt: json['expiresAt'] is String
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
    );
  }

  final String tier;
  final String source; // apple | google | card | crypto
  final DateTime? expiresAt;
}

/// One entry of `/iap/status`'s `sources[]` — a subscription from a single
/// payment source. A user can hold several at once (§1/§9).
class IapSubscriptionSource {
  const IapSubscriptionSource({
    required this.source,
    required this.tier,
    required this.active,
    this.expiresAt,
  });

  factory IapSubscriptionSource.fromJson(Map<String, dynamic> json) {
    return IapSubscriptionSource(
      source: json['source'] is String ? json['source'] as String : '',
      tier: json['tier'] is String ? json['tier'] as String : 'free',
      active: json['active'] is bool ? json['active'] as bool : false,
      expiresAt: json['expiresAt'] is String
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
    );
  }

  final String source;
  final String tier;
  final bool active;
  final DateTime? expiresAt;
}

/// `GET /iap/status` — the effective tier plus every contributing source.
/// Pure read of what the last verify/webhook wrote; cheap to call freely.
class IapStatus {
  const IapStatus({
    required this.tier,
    required this.source,
    this.expiresAt,
    this.sources = const [],
  });

  factory IapStatus.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    return IapStatus(
      tier: json['tier'] is String ? json['tier'] as String : 'free',
      source: json['source'] is String ? json['source'] as String : '',
      expiresAt: json['expiresAt'] is String
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      sources: rawSources is List
          ? rawSources
              .whereType<Map>()
              .map((m) => IapSubscriptionSource.fromJson(
                  Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  final String tier; // effective tier (highest active, §1)
  final String source; // the source backing the effective tier
  final DateTime? expiresAt;
  final List<IapSubscriptionSource> sources;

  bool get hasPaidSubscription =>
      tier != 'free' || sources.any((s) => s.active && s.tier != 'free');
}

// ─── Failures ────────────────────────────────────────────────────────────────

/// How the user should be able to react to a failed purchase/verify
/// (inbox/026 §3 error table).
enum IapErrorKind {
  /// Transient (network, Apple/Google outage, iap_not_configured, expired
  /// session) — "try again" is the honest advice.
  retryable,

  /// Client bookkeeping bug (product_unknown / product_mismatch) — should
  /// never surface in production; show a generic message, log loudly.
  bug,

  /// The transaction itself failed validation (invalid_signature) — the user
  /// can't fix this by retrying; point them at support.
  support,
}

class IapFailure {
  const IapFailure(this.kind, this.message, {this.code});
  final IapErrorKind kind;
  final String message; // already user-presentable
  final String? code;
}

// ─── Purchase pipeline events (repository → controller) ──────────────────────

sealed class IapPurchaseEvent {
  const IapPurchaseEvent(this.productId);

  /// Store query id ([PurchaseDetails.productID]) the event concerns.
  final String productId;
}

/// Store reported the purchase as pending (Ask to Buy / family approval /
/// slow payment method). NOT a failure — distinct UI required (§8).
final class IapPurchasePending extends IapPurchaseEvent {
  const IapPurchasePending(super.productId);
}

/// Store granted the purchase; the server-side verify call is in flight.
final class IapPurchaseVerifying extends IapPurchaseEvent {
  const IapPurchaseVerifying(super.productId);
}

/// Verify succeeded and the transaction was finished/acknowledged.
/// [result] carries the EFFECTIVE tier granted (may differ from the tapped
/// tier — §1 reconciliation).
final class IapPurchaseVerified extends IapPurchaseEvent {
  const IapPurchaseVerified(super.productId, this.result,
      {this.restored = false});
  final IapVerifyResult result;
  final bool restored;
}

final class IapPurchaseFailed extends IapPurchaseEvent {
  const IapPurchaseFailed(super.productId, this.failure);
  final IapFailure failure;
}

final class IapPurchaseCanceled extends IapPurchaseEvent {
  const IapPurchaseCanceled(super.productId);
}
