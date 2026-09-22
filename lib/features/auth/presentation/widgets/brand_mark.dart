import 'package:flutter/material.dart';

/// The brand mark — two overlapping "synapse" circles (teal + violet) in a
/// rounded-square tile. Theme-aware; sits on the auth/landing surfaces.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dot = size * 0.34;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: SizedBox(
          width: dot * 1.6,
          height: dot,
          child: Stack(
            children: [
              // Teal synapse
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Violet synapse, overlapping
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8B6FE6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
