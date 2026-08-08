import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/message_reactions_provider.dart';

/// Thumbs survive a relaunch, and un-rating actually un-rates.
///
/// The rating is stored locally under `reaction:<messageId>` and read back on
/// the next launch. Two things about that round trip are easy to get wrong and
/// invisible until someone reopens the app:
///
///   * A withdrawn rating must not come back. Two independent things stop it:
///     `set` REMOVES the key when the value is zero, and `_hydrate` SKIPS
///     zeros on the way in. Either alone is sufficient — measured, by
///     disabling each in turn and watching the test still pass. It only fails
///     when both are gone. That redundancy is worth knowing before anyone
///     "simplifies" one of them and concludes from a green suite that it did
///     not matter; the test pins the outcome, not either mechanism.
///   * Hydration must ignore the other things in SharedPreferences. It shares
///     a namespace with every other local setting, so a prefix match that is
///     too loose picks up unrelated keys and rates messages nobody rated. This
///     one has no backup: loosening `startsWith` to `contains` fails the test
///     on its own.
///
/// The clamp matters less but is cheap to pin: the store is a tri-state and
/// nothing else should be able to get into it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A fresh container, so `build()` hydrates from whatever prefs hold now —
  /// this is what "relaunch the app" means for this provider.
  Future<ProviderContainer> launch() async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(messageReactionsProvider);
    // _hydrate() is async and fired from build().
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('a rating is remembered across a relaunch', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await launch();
    await first.read(messageReactionsProvider.notifier).set('m1', 1);

    final second = await launch();
    expect(second.read(messageReactionsProvider)['m1'], 1);
  });

  test('clearing a rating does not leave it behind', () async {
    // The failure this prevents: withdraw a thumbs-up, reopen the app, and
    // find it still there — the app disagreeing with a correction the user
    // deliberately made. Reachable only if BOTH the remove-on-zero and the
    // skip-zeros-on-load are dropped; see the note above.
    SharedPreferences.setMockInitialValues({});
    final first = await launch();
    final notifier = first.read(messageReactionsProvider.notifier);
    await notifier.set('m1', 1);
    await notifier.set('m1', 0);

    final second = await launch();
    expect(second.read(messageReactionsProvider).containsKey('m1'), isFalse);
    expect(second.read(messageReactionsProvider.notifier).get('m1'), 0);
  });

  test('a thumbs-down survives too, and stays negative', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await launch();
    await first.read(messageReactionsProvider.notifier).set('m2', -1);

    final second = await launch();
    expect(second.read(messageReactionsProvider)['m2'], -1);
  });

  test('hydration ignores everything that is not a reaction', () async {
    // These live in the same SharedPreferences namespace.
    SharedPreferences.setMockInitialValues({
      'reaction:m1': 1,
      'theme_mode': 2,
      'onboarding_step': -1,
      'reactionish': 1,
    });
    final c = await launch();
    final state = c.read(messageReactionsProvider);

    expect(state, {'m1': 1});
    expect(state.containsKey('theme_mode'), isFalse);
    expect(state.containsKey('onboarding_step'), isFalse,
        reason: 'an unrelated -1 must not become a thumbs-down');
  });

  test('the store stays tri-state whatever it is handed', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await launch();
    final notifier = c.read(messageReactionsProvider.notifier);

    await notifier.set('m1', 7);
    expect(notifier.get('m1'), 1);

    await notifier.set('m2', -7);
    expect(notifier.get('m2'), -1);
  });

  test('an unrated message reads as 0 rather than null', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await launch();
    expect(c.read(messageReactionsProvider.notifier).get('never-touched'), 0);
  });
}
