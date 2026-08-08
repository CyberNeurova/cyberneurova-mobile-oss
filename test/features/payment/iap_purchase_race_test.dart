import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:cyberneurova_mobile/features/payment/data/models/iap_models.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/iap_repository.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/providers/iap_provider.dart';

/// A failing `buy()` must not overwrite a purchase that is already running.
///
/// The store's event stream can beat `buy()`'s return: the platform emits a
/// pending purchase and only afterwards does the call complete — or throw. The
/// `!launched` branch already guarded against that by checking the phase was
/// still `launching`; the `catch` beside it did not, and the difference is
/// money.
///
/// Overwriting `pending` with `failed` does two things at once. It tells the
/// user "The store didn't open. Try again." about a purchase that is in flight,
/// and because `failed` is not `isBusy`, it re-enables the button — so the copy
/// is inviting a second purchase for something the store is already charging
/// for.
class _StubIap implements IapRepository {
  final _events = StreamController<IapPurchaseEvent>.broadcast();

  /// What `buy` should do. Set per test.
  Future<bool> Function()? onBuy;

  @override
  Stream<IapPurchaseEvent> get events => _events.stream;

  void emit(IapPurchaseEvent e) => _events.add(e);

  @override
  Future<bool> buy(IapProduct product, {String? accountId}) =>
      onBuy?.call() ?? Future.value(true);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final product = IapProduct(
    tier: 'pro',
    serverProductId: 'pro_monthly',
    price: r'US$19.99',
    details: ProductDetails(
      id: 'pro_monthly',
      title: 'Pro',
      description: 'Pro plan',
      price: r'US$19.99',
      rawPrice: 19.99,
      currencyCode: 'USD',
    ),
  );

  late _StubIap repo;
  late ProviderContainer container;

  setUp(() {
    repo = _StubIap();
    container = ProviderContainer(
      overrides: [iapRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  IapPurchaseController controller() =>
      container.read(iapPurchaseControllerProvider.notifier);
  IapPurchaseState state() => container.read(iapPurchaseControllerProvider);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a launched purchase sits in launching until the store says otherwise',
      () async {
    await controller().purchase(product);
    expect(state().phase, IapPurchasePhase.launching);
    expect(state().tier, 'pro');
    expect(state().isBusy, isTrue);
  });

  test('a store that never opened reports failure', () async {
    repo.onBuy = () async => false;
    await controller().purchase(product);

    expect(state().phase, IapPurchasePhase.failed);
    expect(state().failure?.kind, IapErrorKind.retryable);
  });

  test('a throwing buy() reports failure when nothing else happened', () async {
    repo.onBuy = () async => throw Exception('platform channel died');
    await controller().purchase(product);

    expect(state().phase, IapPurchasePhase.failed);
  });

  test('a throwing buy() must not clobber a purchase already pending',
      () async {
    // The real interleaving: the store emits pending, THEN buy() throws.
    repo.onBuy = () async {
      repo.emit(const IapPurchasePending('pro_monthly'));
      await Future<void>.delayed(Duration.zero);
      throw Exception('platform channel died after the store took over');
    };

    await controller().purchase(product);
    await settle();

    expect(state().phase, IapPurchasePhase.pending,
        reason: 'the purchase is running; saying it failed is a lie');
    expect(state().isBusy, isTrue,
        reason: 'and the button must stay disabled, or the user buys twice');
  });

  test('a throwing buy() must not clobber a purchase already verifying',
      () async {
    repo.onBuy = () async {
      repo.emit(const IapPurchaseVerifying('pro_monthly'));
      await Future<void>.delayed(Duration.zero);
      throw Exception('late failure');
    };

    await controller().purchase(product);
    await settle();

    expect(state().phase, IapPurchasePhase.verifying);
    expect(state().isBusy, isTrue);
  });

  test('a second tap while busy is ignored', () async {
    // The first line of defence, and the reason the clobber matters: this
    // guard is useless once something has wrongly moved the phase out of busy.
    var calls = 0;
    repo.onBuy = () async {
      calls++;
      return true;
    };

    await controller().purchase(product);
    await controller().purchase(product);

    expect(calls, 1);
  });
}
