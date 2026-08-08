import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/connectivity/connectivity_provider.dart';

/// Quiet, animated strip shown at the top whenever the device is offline.
///
/// **It takes layout space rather than overlaying.** It used to be a `Stack`
/// floating over the content "non-destructively", which in practice meant it
/// covered the app bar — on device the title and the Sign in action were both
/// hidden behind it, so going offline removed navigation from the screen.
/// Occupying 32dp hides nothing. While it is up it also swallows the
/// status-bar inset itself and hands the child a MediaQuery with that top
/// padding removed, or every screen below would count the inset twice and sit
/// 24-48dp too low.
///
/// **Tone is deliberate.** This was a flat amber warning bar. Being offline is
/// not an error the user caused and usually not one they can fix — a hazard
/// colour every time someone steps into a lift is alarming out of proportion
/// to the event. It now uses the app's own surface tones with a slow breathing
/// dot: legible, on-brand, and calm enough to sit at the top of the screen for
/// as long as the connection is out.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: offline
              ? const _OfflineStrip()
              : const SizedBox(width: double.infinity, height: 0),
        ),
        Expanded(
          // The strip has already consumed the status-bar inset; leaving it in
          // the child's MediaQuery would double-count it.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: offline,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _OfflineStrip extends StatefulWidget {
  const _OfflineStrip();

  @override
  State<_OfflineStrip> createState() => _OfflineStripState();
}

class _OfflineStripState extends State<_OfflineStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    // Slow on purpose. A quick blink reads as an alarm; this is closer to
    // breathing, which says "still trying" without demanding attention.
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // An indefinitely looping animation is exactly what motion-sensitivity
    // settings exist for, so honour them and show a static dot instead.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: cs.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (reduceMotion)
                _Dot(color: cs.onSurfaceVariant, opacity: 0.9)
              else
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => _Dot(
                    color: cs.onSurfaceVariant,
                    // Never fades out completely — a dot that vanishes reads
                    // as a rendering glitch rather than a pulse.
                    opacity: 0.35 + (_pulse.value * 0.6),
                  ),
                ),
              const SizedBox(width: 9),
              Text(
                'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '· reconnecting',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }
}
