import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';

/// The empty state for a chat that belongs to an agent surface.
///
/// ## Why the generic one is wrong here
///
/// Opening a new Research session dropped you on "Good afternoon — How can I
/// help you today?" with "Brainstorm ideas", "Explain a concept" and "Help me
/// write code". Nothing on the screen said Research, and two of the three
/// suggestions pointed away from it. From the user's side, the surface they
/// chose simply did not exist once they were inside it.
///
/// A surface already knows what it is for — [AgentSurface] carries the title,
/// the one-line summary and the capability list that the Agents hub shows on
/// its card. Showing the same thing on arrival makes the card and the session
/// agree, and answers "what can I do here" at the only moment it is actually
/// being asked.
///
/// The starters come from the surface too, so they lead further in rather than
/// back out to general chat.
class SurfaceWelcome extends StatelessWidget {
  const SurfaceWelcome({
    super.key,
    required this.surface,
    required this.onPromptTap,
  });

  final AgentSurface surface;
  final void Function(String) onPromptTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // No title here: the app bar already names the surface, and saying
          // "Research" twice on one screen wastes the most valuable rows on a
          // phone. Lead with what it is for.
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(surface.icon, size: 24, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(
            surface.summary,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.5,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 20),

          // What it can actually do, in the user's terms. The same list the
          // hub card shows — someone who tapped through from there should not
          // have to remember it.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in surface.userCapabilities)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          for (final starter in surface.starters)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onPromptTap(starter);
                },
                child: Text(
                  starter,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: cs.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
