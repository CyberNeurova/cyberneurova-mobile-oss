import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Frosted-glass container — the Grok/iOS-26 material used for surfaces that
/// FLOAT over scrolling content (the composer pill, the app-bar backdrop).
///
/// Why this exists: our chat used to lay the composer out in a `Column`
/// BELOW the message list, so the list ended at a hard edge and the last
/// bubble was visually guillotined by the composer's border. Grok instead
/// floats a translucent pill over the list — content slides underneath and
/// blurs out, which reads as depth instead of a wall.
///
/// Both platforms: `BackdropFilter` is cheap on iOS (Metal) and fine on
/// Android (Skia/Impeller) as long as it is CLIPPED to a small region —
/// which [borderRadius] guarantees. Never wrap a full-screen widget in one.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = 18,
    this.opacity,
    this.border = true,
    this.padding,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final BorderRadius? borderRadius;

  /// Gaussian sigma applied to whatever is painted behind this surface.
  final double blur;

  /// Fill alpha over the blur. Defaults are tuned per-brightness: dark mode
  /// needs a heavier veil or bright text bleeds through and hurts legibility
  /// (WCAG contrast on the composer hint text).
  final double? opacity;

  final bool border;
  final EdgeInsetsGeometry? padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(28);
    final fillAlpha = opacity ?? (isDark ? 0.62 : 0.72);

    return ClipRRect(
      borderRadius: radius,
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surfaceContainer.withValues(alpha: fillAlpha),
            borderRadius: radius,
            border: border
                ? Border.all(
                    // Light mode: a hairline at low alpha disappears against
                    // the page, so the pill loses its shape — keep it strong.
                    color: cs.outline.withValues(alpha: isDark ? 0.45 : 0.9),
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Vertical fade that sits between scrolling content and a floating glass
/// surface, so text dissolves into the background instead of colliding with
/// the pill's edge. Paint it directly above the composer.
class ScrimFade extends StatelessWidget {
  const ScrimFade({
    super.key,
    this.height = 28,
    this.reverse = false,
  });

  final double height;

  /// `false` = transparent at top, opaque at bottom (use above a bottom bar).
  /// `true`  = opaque at top, transparent at bottom (use below a top bar).
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: reverse ? Alignment.topCenter : Alignment.bottomCenter,
              end: reverse ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [surface, surface.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
