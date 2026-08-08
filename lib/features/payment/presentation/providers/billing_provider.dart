import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/constants/dev_flags.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/billing_models.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/billing_repository.dart';

final plansProvider = FutureProvider<PlansResponse>((ref) {
  // Dev sandbox: canned plans so the redesigned Plans screen renders with no
  // account/network (same pattern as DevMockChatRepository). Prices are
  // fixtures, not real web pricing.
  if (devAuthBypass) return Future.value(_devPlans);
  return ref.watch(billingRepositoryProvider).getPlans();
});

const _devPlans = PlansResponse(
  monthly: [
    Plan(
      id: 'free',
      name: 'Free',
      tier: 'free',
      price: 0,
      canPurchase: false,
      features: ['Basic models', '2 MB uploads', 'Community support'],
    ),
    Plan(
      id: 'premium',
      name: 'Premium',
      tier: 'premium',
      price: 10,
      features: ['Premium models', '10 MB uploads', 'Voice — speak & listen'],
    ),
    Plan(
      id: 'pro',
      name: 'Pro',
      tier: 'pro',
      price: 25,
      isCurrentPlan: true, // matches the canned /iap/status (pro via apple)
      features: [
        '1.4B units / week',
        'All models incl. flagship',
        '50 images / day',
        'Priority GPU access',
      ],
    ),
    Plan(
      id: 'pro_max',
      name: 'Pro Max',
      tier: 'pro_max',
      price: 60,
      features: ['Everything in Pro', 'Highest limits', 'Early features'],
    ),
  ],
);

final paymentHistoryProvider =
    FutureProvider<PaymentHistoryResponse>((ref) {
  return ref.watch(billingRepositoryProvider).getHistory();
});

/// User's local billing-cycle preference (monthly / yearly). Lives in memory
/// only — persists for the session, resets on app restart.
final billingCycleProvider = StateProvider<bool>((_) => false); // false = monthly

/// User's local payment-method preference. Persists for the session.
/// Backend accepts 'crypto' (Cryptomus gateway) | 'card' — sending 'cryptomus'
/// is rejected with 400 "Invalid payment data".
final paymentMethodProvider = StateProvider<String>((_) => 'crypto');
