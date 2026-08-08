import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';
import 'package:cyberneurova_mobile/features/images/data/repositories/image_repository.dart';
import 'package:cyberneurova_mobile/features/images/presentation/providers/images_provider.dart';

/// The gallery must survive things happening during a slow request.
///
/// `deleteMany` is one round trip per image, so a bulk delete of a dozen
/// pictures is a long window — long enough for a generation to finish and
/// `prepend` a new image at the head. The old code edited a copy of the list
/// taken before the loop and wrote it back at the end, which threw that
/// addition away: the user watched their new image appear and then vanish,
/// with nothing to blame it on.
///
/// It now records which ids were removed and applies that to the list as it
/// stands when the deletes finish, so concurrent additions survive and the
/// deletions still happen.
class _StubImages implements ImageRepository {
  _StubImages(this.initial);

  final List<ImageModel> initial;
  final deleted = <String>[];

  /// One gate per image so a test can land a delete and act between them.
  final gates = <String, Completer<void>>{};

  @override
  Future<ImageListResponse> listImages({String? cursor, int? limit}) async =>
      ImageListResponse(images: initial, hasMore: false);

  @override
  Future<void> deleteImage(String id) {
    deleted.add(id);
    return (gates[id] ??= Completer<void>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ImageModel image(String id) =>
      ImageModel(id: id, url: 'https://x/$id.png', prompt: 'p$id');

  late _StubImages repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _StubImages([image('a'), image('b'), image('c')]);
    container = ProviderContainer(
      overrides: [imageRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(imagesListProvider.future);
  });

  ImagesListNotifier notifier() => container.read(imagesListProvider.notifier);
  List<String> ids() => [
        for (final i in container.read(imagesListProvider).valueOrNull ?? [])
          i.id
      ];

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the gallery starts with what the server sent', () {
    expect(ids(), ['a', 'b', 'c']);
  });

  test('a bulk delete removes exactly the ids asked for', () async {
    final done = notifier().deleteMany(['a', 'c']);
    await settle();
    repo.gates['a']!.complete();
    await settle();
    repo.gates['c']!.complete();
    await settle();

    final result = await done;
    expect(ids(), ['b']);
    expect(result.ok, 2);
    expect(result.failed, 0);
  });

  test('an image generated during a bulk delete is not thrown away', () async {
    final done = notifier().deleteMany(['a', 'c']);
    await settle();
    repo.gates['a']!.complete();
    await settle();

    // The generation the user kicked off earlier lands mid-delete.
    notifier().prepend(image('fresh'));
    expect(ids(), contains('fresh'));

    repo.gates['c']!.complete();
    await settle();
    await done;

    expect(ids(), ['fresh', 'b'],
        reason: 'the new image must outlive a delete it had nothing to do '
            'with, and the deletes must still apply');
  });

  test('a failed delete leaves that image in place', () async {
    final done = notifier().deleteMany(['a', 'b']);
    await settle();
    repo.gates['a']!.completeError(Exception('server said no'));
    await settle();
    repo.gates['b']!.complete();
    await settle();

    final result = await done;
    expect(ids(), ['a', 'c'], reason: 'a is still there; b is gone');
    expect(result.ok, 1);
    expect(result.failed, 1);
  });
}
