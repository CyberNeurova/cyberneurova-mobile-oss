import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/images/data/image_downloader.dart';
import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';
import 'package:cyberneurova_mobile/features/images/presentation/providers/images_provider.dart';
import 'package:cyberneurova_mobile/shared/widgets/authed_network_image.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';

class ImageDetailScreen extends ConsumerWidget {
  const ImageDetailScreen({super.key, required this.imageId});
  final String imageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(imagesListProvider).valueOrNull ?? [];
    final image = list.firstWhere(
      (img) => img.id == imageId,
      orElse: () => ImageModel(
        id: imageId,
        url: '',
        prompt: '',
      ),
    );

    if (image.url.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Image not found')),
      );
    }

    // Full-screen photo viewer: deliberately black in BOTH themes (like the
    // OS Photos app) so the image is the only thing that glows. White icons /
    // text on that scrim are intentional too — do not tokenize to onSurface.
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Save to Photos',
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: () => _save(context, ref, image),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            onPressed: () => _share(context, image),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onPressed: () => _showOptions(context, ref, image),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Pinch-to-zoom full-size image
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // Toggle would need state; for now no-op
              },
              child: Hero(
                tag: 'image-${image.id}',
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: AuthedNetworkImage(
                      imageUrl: image.url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom info panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    image.prompt,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Chip(text: image.model.toUpperCase()),
                      const SizedBox(width: 8),
                      // Chat-team's Ideogram-backed API doesn't return raw
                      // width/height anymore — it returns aspectRatio (e.g.
                      // "1:1", "16:9"). Show that instead.
                      _Chip(text: image.aspectRatio),
                      if (image.createdAt != null) ...[
                        const SizedBox(width: 8),
                        _Chip(text: _formatDate(image.createdAt!)),
                      ],
                    ],
                  ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _share(BuildContext context, ImageModel image) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: image.url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppL10n.of(context).linkCopied),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Download the image + persist to the Photos library via the `gal`
  /// plugin. Auth-fetches the bytes through ImageDownloader so the
  /// server's protected /api/images/<uuid>/view route accepts our
  /// request. Shows feedback throughout — starting / saved / failed —
  /// so the user knows what's happening on slow networks.
  Future<void> _save(
      BuildContext context, WidgetRef ref, ImageModel image) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Saving to Photos…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    try {
      await ref
          .read(imageDownloaderProvider)
          .saveToGallery(
            imageUrl: image.url,
            album: 'CyberNeurova',
            fileName: galleryFileName(prompt: image.prompt, id: image.id),
          );
      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Saved to Photos'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PhotosPermissionDeniedException {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Photos access denied — enable it in Settings → CyberNeurova'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          // Was `$e` — a raw exception under a friendly prefix.
          content: Text("Couldn't save image. ${userMessageFor(context, e)}"),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showOptions(BuildContext context, WidgetRef ref, ImageModel image) {
    HapticFeedback.selectionClick();
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: const Text('Copy prompt'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: image.prompt));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppL10n.of(context).copiedToClipboard),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Generate again'),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(imageGenerationProvider.notifier)
                    .generate(image.prompt);
                context.pop();
                context.pushNamed('image-generate');
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text(
                'Delete',
                style: TextStyle(color: cs.error),
              ),
              onTap: () => _confirmDelete(context, ref, image),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ImageModel image,
  ) async {
    Navigator.pop(context); // close options sheet
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete image?'),
        content: Text(AppL10n.of(dialogCtx).cannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(AppL10n.of(dialogCtx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              AppL10n.of(dialogCtx).delete,
              style:
                  TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.heavyImpact();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(imagesListProvider.notifier).deleteOne(image.id);
      if (!context.mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Image deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Couldn't delete image. "
              '${userMessageFor(context, e)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    // Sits on the photo-viewer's black scrim in both themes, so fixed
    // white-on-black is correct here (not a theming miss).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
