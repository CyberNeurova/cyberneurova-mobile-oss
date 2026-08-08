import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/ask_imagine_switch.dart';
import 'package:cyberneurova_mobile/features/images/data/image_downloader.dart';
import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';
import 'package:cyberneurova_mobile/features/images/presentation/providers/images_provider.dart';
import 'package:cyberneurova_mobile/features/images/presentation/providers/imagine_settings_provider.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/authed_network_image.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';

/// The "Imagine" home surface (Grok pass) — sibling of the Ask/chat
/// surface, reached with a horizontal slide. Layout: header (back ·
/// Imagine · settings), scrollable preview + recent-generations grid,
/// and a chat-composer-style prompt pill pinned at the bottom with a
/// quick-chips row above it.
class ImageGenerateScreen extends ConsumerStatefulWidget {
  const ImageGenerateScreen({super.key});

  @override
  ConsumerState<ImageGenerateScreen> createState() =>
      _ImageGenerateScreenState();
}

class _ImageGenerateScreenState extends ConsumerState<ImageGenerateScreen> {
  final _prompt = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reset the generation state on every entry so the user doesn't
    // see the previous session's image — the provider is kept
    // long-lived globally (not autoDispose) so without this reset
    // the screen would re-mount in the "success" state with a stale
    // image until the user typed a new prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(imageGenerationProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _generate() {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    if (ref.read(imageGenerationProvider).status ==
        GenerationStatus.generating) {
      return;
    }
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    ref.read(imageGenerationProvider.notifier).generate(text);
  }

  /// Save the just-generated image to the Photos library. Same flow as
  /// the image detail screen — go through ImageDownloader so the
  /// auth-protected /api/images/<uuid>/view URL accepts our request.
  Future<void> _saveCurrent(ImageModel image) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Saving to Photos…'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
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
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Saved to Photos'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PhotosPermissionDeniedException {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Photos access denied — enable it in Settings → CyberNeurova'),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't save. ${userMessageFor(context, e)}"),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static const _suggestions = [
    'A cyberpunk city at night, neon lights, rain',
    'Astronaut surfing on a giant wave, dramatic lighting',
    'Glowing CN logo on a circuit board, lightning effects',
    'Minimalist mountain landscape at sunrise',
  ];

  /// Border alpha for the composer pill + chips — same rule the chat
  /// composer uses: light theme needs the full outline (the pill fill is
  /// nearly the page color), dark keeps the subtle 0.35 hairline.
  double get _outlineAlpha =>
      Theme.of(context).brightness == Brightness.light ? 1.0 : 0.35;

  void _openImagineSettings() {
    HapticFeedback.selectionClick();
    // Theme's bottomSheetTheme already gives the radiusXl top shape.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImagineSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gen = ref.watch(imageGenerationProvider);

    // Surface the paywall sheet when ImageGenerationNotifier hits a
    // tier/cap 403. Notifier writes the trigger; we render the sheet.
    // Same pattern chat detail screen uses for upload + TTS paywalls.
    ref.listen<PaywallTrigger?>(pendingPaywallTriggerProvider, (_, next) {
      if (next == null) return;
      ref.read(pendingPaywallTriggerProvider.notifier).state = null;
      showPaywall(context, reason: next.reason, details: next.details);
    });

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        // Imagine is a sibling home surface of Ask, not a pushed detail
        // screen — so it gets the drawer and the same header switch, and
        // "back" is the switch itself rather than a chevron.
        centerTitle: true,
        title: const AskImagineSwitch(mode: AskImagineMode.imagine),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Media library',
            onPressed: () => context.pushNamed('media'),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Imagine settings',
            onPressed: _openImagineSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildScrollArea(cs, gen)),
            _buildComposerBlock(cs, gen),
          ],
        ),
      ),
    );
  }

  // ── Scrollable content: generation preview + recent grid ─────────────────
  Widget _buildScrollArea(ColorScheme cs, GenerationState gen) {
    final images = ref.watch(imagesListProvider);

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        // Active generation preview — only occupies space once the user
        // has kicked off a generation this visit.
        if (gen.status != GenerationStatus.idle)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: _PreviewArea(state: gen),
                  ),
                  if (gen.status == GenerationStatus.success &&
                      gen.image != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _saveCurrent(gen.image!),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Save to Photos'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // Recent generations — reuses the long-lived gallery list
        // provider; freshly generated images are prepended to it by
        // ImageGenerationNotifier so this stays in sync for free.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Recent',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: images.when(
            data: (list) => list.isEmpty
                ? SliverToBoxAdapter(child: _emptyRecents(cs))
                : SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _RecentTile(image: list[i]),
                      childCount: list.length,
                    ),
                  ),
            loading: () => SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, __) => Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                ),
                childCount: 4,
              ),
            ),
            // Recents are a bonus surface — a fetch error shouldn't block
            // generating, so it just collapses.
            error: (_, __) => const SliverToBoxAdapter(
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyRecents(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.image_outlined,
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                  begin: 1.0,
                  end: 1.05,
                  duration: 2000.ms,
                  curve: Curves.easeInOut),
          const SizedBox(height: 12),
          Text(
            'Your creations will appear here',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Bottom block: quick chips + composer pill ────────────────────────────
  Widget _buildComposerBlock(ColorScheme cs, GenerationState gen) {
    final generating = gen.status == GenerationStatus.generating;
    final ratio = ref.watch(imagineAspectRatioProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick chips: the aspect chip mirrors the (UI-only) setting and
          // opens the settings sheet; the rest are prompt suggestions.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _quickChip(
                  cs,
                  icon: Icons.aspect_ratio_rounded,
                  label: ratio,
                  emphasized: true,
                  onTap: _openImagineSettings,
                ),
                const SizedBox(width: 8),
                for (final s in _suggestions) ...[
                  _quickChip(
                    cs,
                    label: s,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _prompt.text = s;
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Prompt pill matching the chat composer's chrome: one rounded
          // radiusXl container, borderless field inside, circular
          // send/generate control on the trailing edge.
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(
                color: cs.outline.withValues(alpha: _outlineAlpha),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _prompt,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !generating,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                        fontSize: 16, height: 1.4, color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Type to imagine…',
                      hintStyle:
                          TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                      // The rounded container IS the chrome — kill the
                      // theme's filled box + borders.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: (_) => _generate(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _generateButton(cs, generating),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 44dp circular generate control. Shows a spinner while the sync
  /// generation request is in flight (same single-state loading the old
  /// screen had — the server gives no progress signal).
  Widget _generateButton(ColorScheme cs, bool generating) {
    if (generating) {
      return Container(
        width: 44,
        height: 44,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHigh),
        padding: const EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.primary),
      );
    }
    return Material(
      color: cs.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _generate,
        child: SizedBox(
          width: 44,
          height: 44,
          child:
              Icon(Icons.arrow_upward_rounded, size: 22, color: cs.onPrimary),
        ),
      ),
    );
  }

  /// Pill chip in the quick row — 44px tap target drawing a 36px pill.
  Widget _quickChip(
    ColorScheme cs, {
    IconData? icon,
    required String label,
    bool emphasized = false,
    required VoidCallback onTap,
  }) {
    final fg = emphasized ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: emphasized
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: emphasized
                  ? cs.primary
                  : cs.outline.withValues(alpha: _outlineAlpha),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                  color: emphasized ? cs.primary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Recent generations tile ─────────────────────────────────────────────────

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.image});
  final ImageModel image;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.pushNamed('image-detail', pathParameters: {'id': image.id});
      },
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: AuthedNetworkImage(
          imageUrl: image.thumbnailUrl ?? image.url,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: cs.outline.withValues(alpha: 0.2)),
          errorWidget: (_, __, ___) => Icon(Icons.broken_image_rounded,
              color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── Imagine settings sheet ──────────────────────────────────────────────────
//
// Grouped rows per the Grok reference — but the backend generate endpoint
// accepts ONLY `prompt` today, so the aspect-ratio selector is honest UI
// state (kept in imagineAspectRatioProvider, NOT sent with requests) and
// every other option row is a disabled "Coming soon" placeholder. Nothing
// here fakes a request parameter.

class _ImagineSettingsSheet extends ConsumerWidget {
  const _ImagineSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(imagineAspectRatioProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Imagine settings',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Aspect ratio',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final o in imagineAspectRatios)
                  _AspectOption(
                    option: o,
                    selected: o.label == selected,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(imagineAspectRatioProvider.notifier).state =
                          o.label;
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              // Honest copy: the selection is a saved preference, not a
              // request parameter — the server only takes a prompt today.
              'Preference only for now — generation uses the server default size.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Divider(
                height: 1,
                thickness: 1,
                color: cs.outline.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            _comingSoonRow(cs,
                icon: Icons.palette_outlined, label: 'Style'),
            _comingSoonRow(cs,
                icon: Icons.filter_none_rounded, label: 'Images per prompt'),
          ],
        ),
      ),
    );
  }

  /// Disabled placeholder row for options the backend doesn't take yet.
  Widget _comingSoonRow(ColorScheme cs,
      {required IconData icon, required String label}) {
    return Opacity(
      opacity: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest,
              ),
              child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                'Coming soon',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visual aspect-ratio option: a proportional outlined rectangle + label.
class _AspectOption extends StatelessWidget {
  const _AspectOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final AspectRatioOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Scale the proportions into a 28px bounding box.
    final maxSide =
        option.width > option.height ? option.width : option.height;
    final w = 28.0 * option.width / maxSide;
    final h = 28.0 * option.height / maxSide;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: selected
                ? cs.primary
                : cs.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 1.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Generation preview states (unchanged flow) ─────────────────────────────

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({required this.state});
  final GenerationState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (state.status) {
        GenerationStatus.idle => const SizedBox.shrink(),
        GenerationStatus.generating =>
          _LoadingPreview(prompt: state.prompt),
        GenerationStatus.success => AuthedNetworkImage(
            imageUrl: state.image!.url,
            fit: BoxFit.cover,
          ).animate().fadeIn(duration: 400.ms).scaleXY(
              begin: 0.95,
              end: 1.0,
              duration: 400.ms,
              curve: Curves.easeOut),
        GenerationStatus.failed => _FailedHint(error: state.error),
      },
    );
  }
}

class _LoadingPreview extends StatelessWidget {
  const _LoadingPreview({required this.prompt});
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        // Animated gradient shimmer
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.15),
                  cs.secondary.withValues(alpha: 0.15),
                  cs.primary.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 1500.ms)
              .then()
              .fadeOut(duration: 1500.ms),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indeterminate spinner — sync server gives no progress
              // signal until done; an indeterminate spinner is more
              // honest than a fake percentage.
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: cs.primary,
                  backgroundColor: cs.outline.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  prompt,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailedHint extends StatelessWidget {
  const _FailedHint({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              userMessageFor(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
