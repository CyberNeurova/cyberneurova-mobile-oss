import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class CnShimmer extends StatelessWidget {
  const CnShimmer({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: cs.surfaceContainer,
      highlightColor: cs.outline.withValues(alpha: 0.5),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
