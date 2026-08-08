import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// Shows that Ask is working, and what it is doing.
///
/// Without this the gap between sending and the first token is completely
/// blank — on a phone, on a slow model, that is several seconds of a screen
/// that looks broken. People re-send, or decide the feature does not work.
///
/// It reports the real stage rather than a generic spinner: "thinking" while
/// the model reasons, and the actual tool once one starts, because "running a
/// command" is genuinely different information from "waiting" and is the part
/// a user most wants to see on a device that is executing things for them.
class AskStatusStrip extends ConsumerStatefulWidget {
  const AskStatusStrip({super.key});

  @override
  ConsumerState<AskStatusStrip> createState() => _AskStatusStripState();
}

class _AskStatusStripState extends ConsumerState<AskStatusStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(streamRunningProvider);
    if (!busy) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tool = ref.watch(activeToolStatusProvider);
    final label = tool == null
        ? 'Thinking'
        : (tool.query?.isNotEmpty == true ? tool.query! : 'Running a command');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 10,
            child: MediaQuery.disableAnimationsOf(context)
                ? _Dots(t: 0.5, color: cs.primary)
                : AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) => _Dots(t: _c.value, color: cs.primary),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Text(
            'on this device',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Three dots rising in sequence. Cheap, and reads as progress rather than as
/// a spinner that could equally mean "stuck".
class _Dots extends StatelessWidget {
  const _Dots({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Builder(builder: (_) {
            // Stagger each dot by a third of the cycle.
            final phase = (t + i / 3) % 1.0;
            // Triangle wave — a sine would linger at the extremes and read as
            // a pulse rather than a travelling wave.
            final lift = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            return Container(
              width: 5,
              height: 5,
              transform: Matrix4.translationValues(0, -2 * lift, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.4 + lift * 0.6),
              ),
            );
          }),
      ],
    );
  }
}
