import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/memory/data/models/memory_model.dart';
import 'package:cyberneurova_mobile/features/memory/data/repositories/memory_repository.dart';
import 'package:cyberneurova_mobile/features/memory/presentation/providers/memory_provider.dart';

/// Deleting a memory that fails must not un-delete the others.
///
/// This screen is where someone goes to take something back — a fact about
/// them the agent should stop knowing. Deletions are one request each and the
/// list invites several in a row, so they overlap. The revert wrote back the
/// whole pre-request snapshot, which resurrected every other memory revoked
/// while that request was in flight.
///
/// The cost here is higher than a row reappearing. The server had accepted
/// those deletions, so the list now disagrees with what the agent will
/// actually be told — and the user, seeing the memory back on screen, has no
/// way to know which state is real.
class _StubMemory implements MemoryRepository {
  _StubMemory(this.initial);

  final List<MemoryModel> initial;

  /// One gate per id so a test can land one deletion while another waits.
  final gates = <String, Completer<void>>{};

  @override
  Future<MemoryListResponse> listMemories({String? cursor}) async =>
      MemoryListResponse(memories: initial, count: initial.length, limit: 100);

  @override
  Future<void> deleteOne(String id) => (gates[id] ??= Completer<void>()).future;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MemoryModel mem(String id) => MemoryModel(id: id, content: 'about $id');

  late _StubMemory repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _StubMemory([mem('a'), mem('b'), mem('c')]);
    container = ProviderContainer(
      overrides: [memoryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(memoryListProvider.future);
  });

  MemoryListNotifier notifier() => container.read(memoryListProvider.notifier);
  List<String> ids() => [
        for (final m
            in container.read(memoryListProvider).valueOrNull?.memories ??
                <MemoryModel>[])
          m.id
      ];
  int count() => container.read(memoryListProvider).valueOrNull?.count ?? -1;
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a delete removes the row immediately', () async {
    unawaited(notifier().deleteOne('b'));
    await settle();
    expect(ids(), ['a', 'c']);
    expect(count(), 2, reason: 'the counter tracks the list');
  });

  test('a failed delete brings back only its own memory', () async {
    final first = notifier().deleteOne('a');
    await settle();
    final second = notifier().deleteOne('c');
    await settle();
    expect(ids(), ['b']);

    // 'c' is accepted by the server.
    repo.gates['c']!.complete();
    await second;

    // 'a' fails, late.
    repo.gates['a']!.completeError(Exception('server said no'));
    await expectLater(first, throwsA(isA<Exception>()));
    await settle();

    expect(ids(), ['a', 'b'],
        reason: 'a comes back at its old position; c stays deleted');
    expect(count(), 2);
  });

  test('the restored memory lands where it was, not at the end', () async {
    // Position matters on a list people scan — a row reappearing somewhere
    // else reads as a different memory.
    final f = notifier().deleteOne('b');
    await settle();
    repo.gates['b']!.completeError(Exception('nope'));
    await expectLater(f, throwsA(isA<Exception>()));
    await settle();

    expect(ids(), ['a', 'b', 'c']);
  });

  test('deleting something already gone is a no-op', () async {
    await notifier().deleteOne('zz');
    expect(ids(), ['a', 'b', 'c']);
    expect(repo.gates, isEmpty,
        reason: 'no request for a row that is not there');
  });
}
