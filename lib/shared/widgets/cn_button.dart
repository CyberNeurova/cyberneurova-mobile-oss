import 'package:flutter/material.dart';

/// Primary app button. Two variants (filled / outlined) sharing one size and
/// shape language: 52px min height, radius 14 (brand radii are 14–18,
/// docs/REDESIGN.md). The label↔spinner swap is animated so a tap doesn't
/// snap-replace content mid-press.
class CnButton extends StatelessWidget {
  const CnButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;

  static const _minSize = Size(double.infinity, 52);
  static final _shape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: c),
      ),
      child: loading
          ? SizedBox(
              key: const ValueKey('spinner'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: outlined ? cs.primary : cs.onPrimary,
                semanticsLabel: label,
              ),
            )
          : Text(label, key: const ValueKey('label')),
    );

    if (outlined) {
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: _minSize,
          shape: _shape,
          side: BorderSide(color: cs.primary),
        ),
        child: child,
      );
    }

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: _minSize,
        shape: _shape,
      ),
      child: child,
    );
  }
}
