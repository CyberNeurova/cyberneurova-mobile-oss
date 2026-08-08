import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/payment/data/models/iap_models.dart';

/// On iOS a subscription tap must never reach web checkout.
///
/// Apple 3.1.1: digital subscriptions are StoreKit-only, and offering an
/// external web payment path for them is a rejection. This app has taken two
/// (build 29 and build 35, both 2.1(b)), and showing any billing UI on iOS at
/// all rides on the payment tap resolving to the store — or, when the store has
/// nothing to sell, to a try-again — but never to the web sheet.
///
/// That rule used to live as an `else if (PlatformFlags.isIOS)` inside a button
/// callback, which cannot be tested off-device: the host is neither platform,
/// so `PlatformFlags.isIOS` is always false and the iOS branch never runs. The
/// decision now takes `isIOS` as an argument for exactly this reason — so the
/// iOS path can be asserted on a desktop test host, which is the only path that
/// can get the app rejected.
void main() {
  group('iOS never routes to web', () {
    test('a real product goes to the store', () {
      expect(
        purchaseRouteFor(hasStoreProduct: true, isIOS: true),
        PurchaseRoute.store,
      );
    });

    test('no product on iOS is a store outage, not web', () {
      // The load-bearing case. Products failing to load — not configured, an
      // App Store outage, or simply not created yet — must not fall through to
      // an external checkout.
      expect(
        purchaseRouteFor(hasStoreProduct: false, isIOS: true),
        PurchaseRoute.storeUnavailable,
      );
    });

    test('web is unreachable on iOS for either product state', () {
      for (final hasProduct in [true, false]) {
        expect(
          purchaseRouteFor(hasStoreProduct: hasProduct, isIOS: true),
          isNot(PurchaseRoute.web),
          reason: 'hasStoreProduct=$hasProduct on iOS must not reach web '
              '(Apple 3.1.1)',
        );
      }
    });
  });

  group('Android keeps its web fallback', () {
    test('a real product still prefers the store', () {
      expect(
        purchaseRouteFor(hasStoreProduct: true, isIOS: false),
        PurchaseRoute.store,
      );
    });

    test('no product on Android falls back to web', () {
      // Play billing is gated in closed testing, so Android genuinely relies on
      // web checkout until the console entries exist. Removing this fallback
      // would leave Android unable to sell at all.
      expect(
        purchaseRouteFor(hasStoreProduct: false, isIOS: false),
        PurchaseRoute.web,
      );
    });
  });
}
