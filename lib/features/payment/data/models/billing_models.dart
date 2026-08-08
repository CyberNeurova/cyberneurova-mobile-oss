import 'package:freezed_annotation/freezed_annotation.dart';

part 'billing_models.freezed.dart';
part 'billing_models.g.dart';

// ─── Plans ───────────────────────────────────────────────────────────────────

@freezed
class Plan with _$Plan {
  const factory Plan({
    required String id,
    required String name,
    required String tier, // free | premium | pro | pro_max
    required num price,
    @Default('USD') String currency,
    @Default(false) bool isCurrentPlan,
    @Default(true) bool canPurchase,
    @Default([]) List<String> features,
  }) = _Plan;

  // Arrow-body fromJson keeps json_serializable able to generate `toJson` for
  // this type, which PlansResponse needs to serialize its List<Plan>. Key
  // normalization lives in [normalize], applied by the parent per element.
  factory Plan.fromJson(Map<String, dynamic> json) => _$PlanFromJson(json);

  /// Backend identifies a plan by `key` (free|premium|pro|pro_max) and has no
  /// separate `tier` field — map both off `key` so the required id/tier aren't
  /// null (which would throw and leave the Plans screen empty).
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      ...m,
      'id': m['id'] ?? m['key'] ?? '',
      'tier': m['tier'] ?? m['key'] ?? 'free',
      'name': m['name'] ?? m['title'] ?? m['displayName'] ?? '',
      // Gateways sometimes send price as a string ("9.99") — coerce to num.
      'price': m['price'] is num ? m['price'] : (num.tryParse('${m['price']}') ?? 0),
    };
  }
}

@freezed
class PlansResponse with _$PlansResponse {
  const factory PlansResponse({
    @Default([]) List<Plan> monthly,
    @Default([]) List<Plan> yearly,
    @Default(['cryptomus', 'card']) List<String> paymentMethods,
    PromotionInfo? promotion,
  }) = _PlansResponse;

  // Constructs directly (not via _$PlansResponseFromJson) because freezed only
  // generates the json glue for the plain arrow-redirect form; a normalizing
  // body has to build the object itself. Backend nests the lists under
  // `plans: {monthly: [...], yearly: [...]}` and keys plans by `key`.
  factory PlansResponse.fromJson(Map<String, dynamic> json) {
    final plans = json['plans'];
    // The user's current tier is a single top-level `currentTier`, not a
    // per-plan flag — mark the matching plan so the UI shows "Current plan"
    // and hides the upgrade CTA for the tier the user already owns.
    final currentTier =
        json['currentTier'] is String ? json['currentTier'] as String : null;
    List<Plan> parse(dynamic raw) => (raw is List ? raw : const [])
        .whereType<Map>()
        .map((p) {
          final m = Plan.normalize(p);
          if (currentTier != null && m['tier'] == currentTier) {
            m['isCurrentPlan'] = true;
          }
          return Plan.fromJson(m);
        })
        .toList();
    // Payment methods: the gateway value is 'crypto' (not 'cryptomus').
    final rawMethods = json['paymentMethods'];
    final methods = (rawMethods is List
            ? rawMethods.map((e) => e.toString())
            : const ['crypto', 'card'])
        .map((m) => m == 'cryptomus' ? 'crypto' : m)
        .toList();
    final promo = json['promotion'];
    return PlansResponse(
      monthly: parse(json['monthly'] ?? (plans is Map ? plans['monthly'] : null)),
      yearly: parse(json['yearly'] ?? (plans is Map ? plans['yearly'] : null)),
      paymentMethods: methods,
      promotion: promo is Map
          ? PromotionInfo.fromJson(Map<String, dynamic>.from(promo))
          : null,
    );
  }
}

@freezed
class PromotionInfo with _$PromotionInfo {
  const factory PromotionInfo({
    String? title,
    String? description,
    @Default(0) int discountPercent,
    DateTime? expiresAt,
  }) = _PromotionInfo;

  factory PromotionInfo.fromJson(Map<String, dynamic> json) =>
      _$PromotionInfoFromJson(json);
}

// ─── Invoice / Checkout ──────────────────────────────────────────────────────

@freezed
class CreatedInvoice with _$CreatedInvoice {
  const factory CreatedInvoice({
    required String invoiceId,
    required String invoiceUrl,
    DateTime? expiresAt,
    String? paymentMethod,
  }) = _CreatedInvoice;

  // Constructs directly (see PlansResponse note). Gateways/back-ends name these
  // differently — coalesce so the required fields are never null (which would
  // throw and break checkout). A nested `invoice`/`data` wrapper is tolerated.
  factory CreatedInvoice.fromJson(Map<String, dynamic> json) {
    // Real contract returns `{payment: {invoiceId, invoiceUrl, …}}`; tolerate
    // `invoice`/`data` wrappers and a bare object too.
    final inner = (json['payment'] is Map)
        ? Map<String, dynamic>.from(json['payment'] as Map)
        : (json['invoice'] is Map)
            ? Map<String, dynamic>.from(json['invoice'] as Map)
            : (json['data'] is Map)
                ? Map<String, dynamic>.from(json['data'] as Map)
                : json;
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = json[k] ?? inner[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return '';
    }

    final method = json['paymentMethod'] ?? inner['paymentMethod'];
    final expires = json['expiresAt'] ?? inner['expiresAt'];
    return CreatedInvoice(
      invoiceId: pick(['invoiceId', 'id']),
      invoiceUrl: pick(
          ['invoiceUrl', 'url', 'paymentUrl', 'checkoutUrl', 'invoice_url']),
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      paymentMethod: method is String ? method : null,
    );
  }
}

@freezed
class InvoiceStatus with _$InvoiceStatus {
  const factory InvoiceStatus({
    required String status, // pending | paid | expired | failed
    DateTime? paidAt,
    Map<String, dynamic>? subscription,
  }) = _InvoiceStatus;

  factory InvoiceStatus.fromJson(Map<String, dynamic> json) =>
      _$InvoiceStatusFromJson(json);

  // Convenience flags
}

extension InvoiceStatusX on InvoiceStatus {
  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';
  bool get isFailed => status == 'failed';
  bool get isTerminal => isPaid || isExpired || isFailed;
}

// ─── History ─────────────────────────────────────────────────────────────────

@freezed
class HistoricalPayment with _$HistoricalPayment {
  const factory HistoricalPayment({
    required String id,
    required String tier,
    required num amount,
    @Default('USD') String currency,
    required String status,
    String? paymentMethod,
    DateTime? createdAt,
    DateTime? paidAt,
  }) = _HistoricalPayment;

  factory HistoricalPayment.fromJson(Map<String, dynamic> json) =>
      _$HistoricalPaymentFromJson(json);

  /// Backend returns the id as `invoiceId`. Coalesce the required string fields
  /// and coerce `amount` — a single drifted row (string/Decimal128 amount, a
  /// missing tier/status) used to throw and error the WHOLE history screen.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      ...m,
      'id': m['id'] ?? m['invoiceId'] ?? '',
      'tier': m['tier'] ?? m['subscriptionTier'] ?? 'free',
      'status': m['status'] ?? 'unknown',
      'amount': _coerceAmount(m['amount']),
    };
  }

  // amount may arrive as a num, a string ("120.00"), or a Mongo Decimal128
  // (`{$numberDecimal: "120.00"}`) — never let it be a non-num the cast rejects.
  static num _coerceAmount(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    if (v is Map && v[r'$numberDecimal'] != null) {
      return num.tryParse('${v[r'$numberDecimal']}') ?? 0;
    }
    return 0;
  }
}

@freezed
class PaymentHistoryResponse with _$PaymentHistoryResponse {
  const factory PaymentHistoryResponse({
    @Default([]) List<HistoricalPayment> payments,
    String? nextCursor,
    @Default(false) bool hasMore,
  }) = _PaymentHistoryResponse;

  // Constructs directly (see PlansResponse note). Tolerates a {success,
  // data:{payments}} envelope or top-level payments, and skips any single
  // malformed row rather than erroring the whole history screen.
  factory PaymentHistoryResponse.fromJson(Map<String, dynamic> json) {
    final src = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final raw = src['payments'];
    final payments = <HistoricalPayment>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) {
          try {
            payments
                .add(HistoricalPayment.fromJson(HistoricalPayment.normalize(p)));
          } catch (_) {/* skip a malformed row */}
        }
      }
    }
    return PaymentHistoryResponse(
      payments: payments,
      nextCursor: src['nextCursor'] is String ? src['nextCursor'] as String : null,
      hasMore: src['hasMore'] is bool ? src['hasMore'] as bool : false,
    );
  }
}
