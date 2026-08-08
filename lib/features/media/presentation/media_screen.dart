import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/features/images/presentation/screens/images_gallery_screen.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';

/// Media page — Images gallery only.
///
/// History: this used to be a two-tab screen (Images + Videos), but
/// the video generation feature was removed from the mobile UI on
/// 2026-06-05 (user decision). The route name and path stay the
/// same so existing navigation deep-links keep working; the screen
/// is now just a thin header + the gallery.
class MediaScreen extends ConsumerWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar — menu (reopens sidebar) + title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.menu_rounded, size: 24),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Images',
                    // serifDisplay defaults to the dark palette's near-white;
                    // pass the live scheme's ink so light mode reads.
                    style: AppTheme.serifDisplay(
                        size: 22,
                        weight: FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Expanded(child: ImagesGalleryScreen()),
          ],
        ),
      ),
    );
  }
}
