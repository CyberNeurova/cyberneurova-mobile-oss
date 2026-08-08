import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';

/// What this surface can do, in the user's terms.
///
/// ## Why it is worth a sheet
///
/// The three agent surfaces look alike and behave differently, and until now
/// nothing told the user which one reaches their files, which one reaches their
/// network, and which one — a plain chat — reaches nothing at all. That gap is
/// the whole reason behind "it said it wrote the code, but the shell is empty":
/// the session genuinely could not write anything, and the surface never said
/// so.
///
/// A sheet rather than a permanent banner: this is read once and then in the
/// way. On a phone, a strip of explanatory text at the top of every list is
/// screen the session list should have had.
Future<void> showSurfaceCapabilities(
  BuildContext context,
  AgentSurface surface,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SurfaceCapabilitiesSheet(surface: surface),
  );
}

class _SurfaceCapabilitiesSheet extends StatelessWidget {
  const _SurfaceCapabilitiesSheet({required this.surface});

  final AgentSurface surface;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              surface.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              surface.summary,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'What it can do',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final line in surface.userCapabilities)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 10),
                      child: Icon(Icons.check_rounded,
                          size: 17, color: cs.primary),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 10),
                    child: Icon(Icons.smartphone_rounded,
                        size: 17, color: cs.onSurfaceVariant),
                  ),
                  Expanded(
                    // The one fact that distinguishes these surfaces from an
                    // ordinary chat, and the one users get wrong. Said here
                    // rather than implied by the tool list.
                    child: Text(
                      'This work runs on your phone, not on our servers. An '
                      'ordinary chat cannot do any of it.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app-bar affordance that opens the sheet.
class SurfaceCapabilitiesAction extends StatelessWidget {
  const SurfaceCapabilitiesAction({super.key, required this.surface});

  final AgentSurface surface;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'What ${surface.title} can do',
      icon: const Icon(Icons.info_outline_rounded),
      onPressed: () => showSurfaceCapabilities(context, surface),
    );
  }
}
