import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/billing_models.dart';

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(apiClientProvider));
});

/// In-app billing flow for all platforms. Per [PlatformFlags.showBilling] the
/// plans + upgrade CTAs are shown everywhere (incl. iOS) and checkout opens in
/// an in-app browser (the "Starlink pattern") — see that flag for the rationale.
///
/// Pipeline:
///   1. `getPlans()`      → render Plans screen
///   2. `createInvoice()` → returns `{invoiceUrl}` for the cryptomus/card gateway
///   3. open `invoiceUrl` in an in-app webview
///   4. poll `getStatus()` every ~3s until `isTerminal`
///   5. on paid → refresh `/auth/me` and dismiss webview
class BillingRepository {
  BillingRepository(this._client);
  final ApiClient _client;

  Future<PlansResponse> getPlans() async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.PAYMENT_PLANS,
    );
    return PlansResponse.fromJson(res.data!);
  }

  Future<CreatedInvoice> createInvoice({
    required String tier, // premium | pro | pro_max (NOT planId — that 400s)
    required String paymentMethod, // crypto | cryptomus | card
    bool isYearly = false,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.PAYMENT_CREATE,
      // Real contract (MOBILE_API.md): {tier, paymentMethod, isYearly}. Sending
      // `planId` (or any extra field) is rejected 400 INVALID_INPUT.
      data: {
        'tier': tier,
        'paymentMethod': paymentMethod,
        'isYearly': isYearly,
      },
    );
    return CreatedInvoice.fromJson(res.data!);
  }

  Future<InvoiceStatus> getStatus(String invoiceId) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.PAYMENT_STATUS,
      data: {'invoiceId': invoiceId},
    );
    // Real contract wraps the result under `payment`.
    final body = res.data!;
    final inner = body['payment'] is Map
        ? Map<String, dynamic>.from(body['payment'] as Map)
        : body;
    return InvoiceStatus.fromJson(inner);
  }

  /// Poll the invoice until status reaches a terminal state or [timeout] elapses.
  /// Yields each status snapshot so callers can update progress UI.
  Stream<InvoiceStatus> watchInvoice(
    String invoiceId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 30),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await getStatus(invoiceId);
        yield s;
        if (s.isTerminal) return;
      } catch (e) {
        // Transient error — keep polling, callers can react via status
      }
      await Future.delayed(interval);
    }
  }

  Future<PaymentHistoryResponse> getHistory({int limit = 20}) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.PAYMENT_HISTORY,
      queryParameters: {'limit': limit},
    );
    return PaymentHistoryResponse.fromJson(res.data!);
  }

  Future<({bool cancelled, String? accessUntil, String? tier})>
      cancelSubscription() async {
    // The chat-app cancel route lives on /user/subscription/cancel — outside
    // the /payment/ namespace. We hardcode the path here.
    final res = await _client.post<Map<String, dynamic>>(
      '/user/subscription/cancel',
    );
    final data = res.data!;
    return (
      cancelled: data['cancelled'] is bool ? data['cancelled'] as bool : true,
      accessUntil: data['accessUntil'] is String ? data['accessUntil'] as String : null,
      tier: data['tier'] is String ? data['tier'] as String : null,
    );
  }
}
