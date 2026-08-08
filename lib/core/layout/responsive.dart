import 'package:flutter/material.dart';

/// Layout breakpoints + helpers. Used by screens that need to behave
/// differently on phones vs tablets without us scattering MediaQuery checks.
///
/// The "tablet" threshold matches Material's standard: a device is a tablet
/// when its shortest side is ≥ 600dp. iPad mini (744 shortest) and any
/// 10"+ Android tablet qualify. Foldables in folded mode stay below 600dp
/// shortest, so they're treated as phones — correct.
class Responsive {
  Responsive._();

  /// Material's standard tablet cutoff. shortestSide ≥ this → tablet.
  static const double tabletShortestSide = 600;

  /// Cap content width on wide screens so long lines stay readable and the
  /// UI doesn't look like a phone stretched across an iPad Pro 12.9".
  static const double contentMaxWidth = 720;

  /// Drawer width on tablets — fixed so it doesn't eat 80% of an iPad.
  static const double tabletDrawerWidth = 320;

  static bool isTablet(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return s.shortestSide >= tabletShortestSide;
  }

  /// Returns a drawer width that fits the device.
  static double drawerWidth(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    if (s.shortestSide >= tabletShortestSide) {
      return tabletDrawerWidth;
    }
    return s.width * 0.82;
  }
}

/// Wraps its `child` in a centered, max-width container on wide screens.
/// On phones this is a no-op (returns the child unchanged) so we don't
/// constrain anything we don't have to.
class MaxWidthContent extends StatelessWidget {
  const MaxWidthContent({
    super.key,
    required this.child,
    this.maxWidth = Responsive.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isTablet(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
