import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/capabilities/data/models/capability_models.dart';
import 'package:cyberneurova_mobile/features/capabilities/data/repositories/capabilities_repository.dart';
import 'package:cyberneurova_mobile/features/capabilities/presentation/providers/capabilities_provider.dart';

/// A failed toggle must undo itself and nothing else.
///
/// Each switch is its own request and the screen lets you flip several without
/// waiting, so requests overlap routinely. The revert used to write back the
/// whole list as it was before the failing request started — which also undid
/// every other switch flipped meanwhile, including ones the server had already
/// accepted. The switches would spring back to a state the server disagreed
/// with, silently, until something forced a refresh.
///
/// That is worse than a failed toggle: the user is told the change did not
/// happen when it did.
class _StubCaps implements CapabilitiesRepository {
  _StubCaps(this.skills);

  final List<CapabilityModel> skills;
  final gates = <String, Completer<void>>{};

  @override
  Future<CapabilityListResponse> listSkills() async =>
      CapabilityListResponse(items: skills);

  @override
  Future<void> toggleSkill(String id, bool enabled) =>
      (gates[id] ??= Completer<void>()).future;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CapabilityModel cap(String id, {bool enabled = false}) =>
      CapabilityModel(id: id, name: id, enabled: enabled);

  late _StubCaps repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _StubCaps([cap('web'), cap('files'), cap('shell')]);
    container = ProviderContainer(
      overrides: [capabilitiesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(skillsProvider.future);
  });

  SkillsNotifier notifier() => container.read(skillsProvider.notifier);
  Map<String, bool> enabled() => {
        for (final s in container.read(skillsProvider).valueOrNull ?? [])
          s.id: s.enabled,
      };
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a toggle flips optimistically, before the server answers', () async {
    unawaited(notifier().toggle('web', true));
    await settle();
    expect(enabled()['web'], isTrue);
  });

  test('a successful toggle stays flipped', () async {
    final done = notifier().toggle('web', true);
    await settle();
    repo.gates['web']!.complete();
    await done;
    expect(enabled()['web'], isTrue);
  });

  test('a failed toggle reverts only itself', () async {
    // Flip two switches; the first fails, the second succeeds.
    final first = notifier().toggle('web', true);
    await settle();
    final second = notifier().toggle('files', true);
    await settle();

    repo.gates['files']!.complete();
    await second;
    expect(enabled()['files'], isTrue);

    repo.gates['web']!.completeError(Exception('server said no'));
    await expectLater(first, throwsA(isA<Exception>()));
    await settle();

    expect(enabled()['web'], isFalse, reason: 'the failure undoes its own row');
    expect(enabled()['files'], isTrue,
        reason: 'a switch the server accepted must not spring back');
  });

  test('the failure still surfaces to the caller', () async {
    // The screen shows a snackbar off this; swallowing it would leave the
    // switch flipping back with no explanation.
    final f = notifier().toggle('web', true);
    await settle();
    repo.gates['web']!.completeError(Exception('nope'));
    await expectLater(f, throwsA(isA<Exception>()));
  });

  test('reverting puts back the value it had, not the opposite of now',
      () async {
    // 'shell' starts enabled. Turning it off and failing must restore ON —
    // and it must stay ON even though the row was toggled again meanwhile.
    repo.skills[2] = cap('shell', enabled: true);
    final fresh = ProviderContainer(
      overrides: [capabilitiesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(fresh.dispose);
    await fresh.read(skillsProvider.future);

    final f = fresh.read(skillsProvider.notifier).toggle('shell', false);
    await settle();
    repo.gates['shell']!.completeError(Exception('nope'));
    await expectLater(f, throwsA(isA<Exception>()));
    await settle();

    final state = {
      for (final s in fresh.read(skillsProvider).valueOrNull ?? [])
        s.id: s.enabled,
    };
    expect(state['shell'], isTrue);
  });
}
