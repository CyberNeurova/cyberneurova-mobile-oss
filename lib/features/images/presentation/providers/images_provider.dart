import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';
import 'package:cyberneurova_mobile/features/images/data/repositories/image_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';

// ─── Gallery list — paginated ───────────────────────────────────────
final imagesListProvider =
    AsyncNotifierProvider<ImagesListNotifier, List<ImageModel>>(
  ImagesListNotifier.new,
);

class ImagesListNotifier extends AsyncNotifier<List<ImageModel>> {
  String? _cursor;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  Future<List<ImageModel>> build() async {
    _cursor = null;
    _hasMore = true;
    return _fetch();
  }

  Future<List<ImageModel>> _fetch() async {
    final res =
        await ref.read(imageRepositoryProvider).listImages(cursor: _cursor);
    _cursor = res.nextCursor;
    // See ChatListNotifier._fetch: `hasMore` without a `nextCursor`
    // cannot be acted on, and trusting it re-requests page one for ever.
    _hasMore = res.hasMore && res.nextCursor != null;
    return res.images;
  }

  Future<void> loadMore() async {
    // Sahachiel: re-entrancy guard — see ChatListNotifier.loadMore. Prevents
    // duplicate-page fetches + page-skips on a fast scroll.
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final more = await _fetch();
      // After the fetch, never before — see ChatListNotifier.loadMore. The
      // gallery is mutated while a page is in flight: `prepend` puts a
      // freshly generated image at the head, `deleteOne` removes a row.
      // Appending onto a stale snapshot undid both, so an image deleted
      // mid-scroll reappeared and a just-generated one disappeared.
      final current = state.valueOrNull ?? [];
      // No image twice in the grid, whatever the server does with the
      // cursor; and a page that adds nothing new ends the pagination.
      final seen = {for (final i in current) i.id};
      final fresh = [
        for (final i in more)
          if (!seen.contains(i.id)) i
      ];
      if (fresh.isEmpty) {
        _hasMore = false;
        return;
      }
      state = AsyncData([...current, ...fresh]);
    } finally {
      _loadingMore = false;
    }
  }

  /// Insert a freshly-generated image at the head of the gallery so
  /// the user sees their new creation without waiting for a refetch.
  void prepend(ImageModel image) {
    final current = state.valueOrNull ?? [];
    state = AsyncData([image, ...current]);
  }

  /// Delete an image. Calls the server first (web-origin
  /// `DELETE /api/images/<uuid>`, see ImageRepository.deleteImage),
  /// then removes from local state on success. Throws to the caller
  /// on failure so the UI can surface an error.
  Future<void> deleteOne(String imageId) async {
    await ref.read(imageRepositoryProvider).deleteImage(imageId);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((i) => i.id != imageId).toList());
  }

  /// Bulk delete. Server endpoint is single-image-per-call today, so
  /// we loop sequentially. Returns a (ok, failed) pair so the caller
  /// can report partial success in a snackbar.
  Future<({int ok, int failed})> deleteMany(Iterable<String> ids) async {
    final repo = ref.read(imageRepositoryProvider);
    // Track WHAT was deleted rather than editing a copy of the list, then
    // apply that to the list as it stands at the end. A bulk delete is one
    // round trip per image, so the gallery can gain a freshly generated
    // image partway through; writing back an edited pre-loop snapshot threw
    // that away.
    final removed = <String>{};
    var ok = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.deleteImage(id);
        removed.add(id);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    state = AsyncData([
      for (final image in state.valueOrNull ?? <ImageModel>[])
        if (!removed.contains(image.id)) image,
    ]);
    return (ok: ok, failed: failed);
  }
}

// ─── Gallery multi-select ───────────────────────────────────────────
//
// Empty set = normal mode (tap navigates to detail).
// Non-empty set = selection mode (tap toggles; long-press is moot
// because the mode is already active; AppBar shows count + bulk
// actions). Same pattern as the drawer's chat multi-select.

final selectedImagesProvider =
    NotifierProvider<SelectedImagesNotifier, Set<String>>(
  SelectedImagesNotifier.new,
);

class SelectedImagesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void toggle(String id) {
    if (id.isEmpty) return;
    final next = {...state};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = next;
  }
  void clear() => state = const {};
}

// ─── Single-image generation state ──────────────────────────────────
//
// Server is synchronous now (Ideogram returns image bytes in ~15s),
// so we only need three states: idle / generating / success / failed.
// The previous "polling" state from the ComfyUI era is gone.
enum GenerationStatus { idle, generating, success, failed }

class GenerationState {
  const GenerationState({
    this.status = GenerationStatus.idle,
    this.prompt = '',
    this.image,
    this.error,
  });

  final GenerationStatus status;
  final String prompt;
  final ImageModel? image;

  /// The thrown object, NOT a message.
  ///
  /// This used to be `e.toString()`, which put the server's own wording in
  /// front of the user unfiltered — on device 2026-08-05 a failed generation
  /// showed the word **"fetch failed"** under a red icon, which is Node's
  /// network error and means nothing to anyone holding a phone. Keeping the
  /// exception lets the view render it through `userMessageFor`, the same
  /// mapping the rest of the app uses.
  final Object? error;

  GenerationState copyWith({
    GenerationStatus? status,
    String? prompt,
    ImageModel? image,
    Object? error,
  }) =>
      GenerationState(
        status: status ?? this.status,
        prompt: prompt ?? this.prompt,
        image: image ?? this.image,
        error: error ?? this.error,
      );
}

final imageGenerationProvider =
    NotifierProvider<ImageGenerationNotifier, GenerationState>(
  ImageGenerationNotifier.new,
);

class ImageGenerationNotifier extends Notifier<GenerationState> {
  @override
  GenerationState build() => const GenerationState();

  Future<void> generate(String prompt) async {
    // Explicit constructor (not copyWith) — copyWith couldn't null the
    // previous `image` because its `??` fallback kept it. Result was
    // that tapping Generate again briefly showed the prior image
    // before the new one arrived (user reported it as "previous image
    // shows when I click generate").
    state = GenerationState(
      status: GenerationStatus.generating,
      prompt: prompt,
    );

    try {
      final result =
          await ref.read(imageRepositoryProvider).generateImage(prompt: prompt);

      // Build an ImageModel from the generate response. We don't have
      // the imageId on this path (server-side embeds it in the URL),
      // so derive a stable-ish id from the URL — the gallery list will
      // refetch and get the real DB record on next pull-to-refresh.
      final fakeId =
          Uri.parse(result.url).pathSegments.lastWhere(
                (s) => s != 'view' && s.isNotEmpty,
                orElse: () => DateTime.now().millisecondsSinceEpoch.toString(),
              );

      final freshImage = ImageModel(
        id: fakeId,
        url: result.url,
        thumbnailUrl: result.url,
        prompt: prompt,
        createdAt: DateTime.now(),
      );

      // Optimistically prepend to the gallery so the user sees the new
      // image without round-tripping the list endpoint. Next refresh
      // reconciles with the canonical DB record.
      ref.read(imagesListProvider.notifier).prepend(freshImage);

      state = state.copyWith(
        status: GenerationStatus.success,
        image: freshImage,
      );
    } catch (e) {
      // Free-tier hit daily cap, or premium feature gated. Show the
      // paywall via the shared trigger provider — chat detail screen
      // listens and surfaces the contextualized sheet. Keep generation
      // status as failed but clear the prompt so a retry doesn't loop.
      if (e is ForbiddenException &&
          (e.code == 'TIER_REQUIRED' ||
              e.code == 'INSUFFICIENT_UNITS' ||
              e.code == 'IMAGE_GEN_CAP')) {
        ref.read(pendingPaywallTriggerProvider.notifier).state =
            const PaywallTrigger(reason: PaywallReason.imageGenCap);
        state = state.copyWith(
          status: GenerationStatus.idle,
          error: null,
        );
        return;
      }
      state = state.copyWith(
        status: GenerationStatus.failed,
        error: e,
      );
    }
  }

  void reset() => state = const GenerationState();
}
