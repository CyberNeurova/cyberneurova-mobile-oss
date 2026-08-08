import 'package:flutter/material.dart';

/// Wraps [child] with a subtle press-scale for tactile feedback — the small
/// "give" on touch that makes an interface feel responsive and premium
/// (Material/HIG `scale-feedback`: 0.95–1.05 on press).
///
/// Use it on cards, chips, suggested prompts, list rows, and custom tap
/// targets that don't already have an ink ripple. Honors reduced-motion
/// (`MediaQuery.disableAnimations`) — the scale is skipped, the tap still works.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Pressed scale target (default 0.96). Smaller = more pronounced.
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final target = (_down && !reduceMotion) ? widget.scale : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: target,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
