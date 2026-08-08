import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';
import 'package:cyberneurova_mobile/features/images/presentation/providers/images_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/authed_network_image.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

class ImagesGalleryScreen extends ConsumerWidget {
  const ImagesGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(imagesListProvider);
    final selected = ref.watch(selectedImagesProvider);
    final isSelectionMode = selected.isNotEmpty;

    return Scaffold(
      floatingActionButton: isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.mediumImpact();
                context.pushNamed('image-generate');
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Generate'),
            ),
      body: Column(
        children: [
          // Selection action bar — a grouped-card-styled inline bar instead of
          // an AppBar, so the chrome matches the settings-card system.
          if (isSelectionMode)
            _SelectionBar(
              count: selected.length,
              onCancel: () {
                HapticFeedback.lightImpact();
                ref.read(selectedImagesProvider.notifier).clear();
              },
              onDelete: () => _confirmBulkDelete(context, ref, selected),
            ),
          Expanded(
            child: images.when(
              loading: () => const _GalleryShimmer(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.refresh(imagesListProvider.future),
              ),
              data: (list) => list.isEmpty
                  ? const _EmptyImages()
                  : RefreshIndicator(
                      onRefresh: () {
                        HapticFeedback.selectionClick();
                        return ref.refresh(imagesListProvider.future);
                      },
                      // Fetch the next page near the bottom. `loadMore` was defined,
                      // guarded against re-entrancy, and called by NOTHING — so the list
                      // stopped at one page of AppConstants.defaultPageLimit and every
                      // older row was unreachable. Same fault as the chat drawer.
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          final m = n.metrics;
                          if (m.axis == Axis.vertical &&
                              m.pixels >= m.maxScrollExtent - 400) {
                            ref.read(imagesListProvider.notifier).loadMore();
                          }
                          return false;
                        },
                        child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _ImageTile(image: list[i])
                            .animate(
                                delay: Duration(milliseconds: i * 35))
                            .fadeIn(duration: 300.ms)
                            .scaleXY(
                                begin: 0.95,
                                end: 1.0,
                                duration: 300.ms,
                                curve: Curves.easeOut),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmBulkDelete(
  BuildContext context,
  WidgetRef ref,
  Set<String> ids,
) async {
  final cs = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text('Delete ${ids.length} images?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text('Delete', style: TextStyle(color: cs.error)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  HapticFeedback.heavyImpact();

  final messenger = ScaffoldMessenger.maybeOf(context);
  final result =
      await ref.read(imagesListProvider.notifier).deleteMany(ids);
  ref.read(selectedImagesProvider.notifier).clear();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(result.failed == 0
          ? '${result.ok} images deleted'
          : '${result.ok} deleted, ${result.failed} failed'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ─── Selection action bar (grouped-card chrome) ──────────────────────────────

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
  });
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.close_rounded, color: cs.onSurface),
              tooltip: 'Cancel',
              onPressed: onCancel,
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 150.ms);
  }
}

// ─── Grid tile ───────────────────────────────────────────────────────────────

class _ImageTile extends ConsumerWidget {
  const _ImageTile({required this.image});
  final ImageModel image;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedImagesProvider);
    final isSelectionMode = selected.isNotEmpty;
    final isSelected = selected.contains(image.id);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (isSelectionMode) {
          ref.read(selectedImagesProvider.notifier).toggle(image.id);
          return;
        }
        context.pushNamed('image-detail', pathParameters: {'id': image.id});
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        ref.read(selectedImagesProvider.notifier).toggle(image.id);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          color: cs.surfaceContainer,
          border: isSelected
              ? Border.all(color: cs.primary, width: 3)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'image-${image.id}',
              child: AuthedNetworkImage(
                imageUrl: image.thumbnailUrl ?? image.url,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: cs.outline.withValues(alpha: 0.2)),
                errorWidget: (_, __, ___) => Icon(
                    Icons.broken_image_rounded,
                    color: cs.onSurfaceVariant),
              ),
            ),
            // Selection checkmark (top-right) when in selection mode.
            // Fixed white/black54 here is deliberate: the badge floats over
            // arbitrary photo content in both themes, so theme tokens (which
            // flip with brightness) would vanish against some images.
            if (isSelectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? cs.primary : Colors.black54,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : null,
                ),
              ),
            // Gradient overlay + prompt — a black photo-scrim with white text
            // in BOTH themes (it sits on the image, not on a surface).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Text(
                  image.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyImages extends StatelessWidget {
  const _EmptyImages();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                    size: 64, color: cs.primary.withValues(alpha: 0.3))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    begin: 1.0,
                    end: 1.08,
                    duration: 2000.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: 16),
            Text(
              'No images yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Describe an image and let AI create it.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                context.pushNamed('image-generate');
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Loading skeleton ────────────────────────────────────────────────────────

class _GalleryShimmer extends StatelessWidget {
  const _GalleryShimmer();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const CnShimmer(
          width: double.infinity,
          height: 200,
          radius: AppTheme.radiusMd),
    );
  }
}
