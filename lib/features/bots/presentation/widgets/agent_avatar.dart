import 'package:flutter/material.dart';

/// An agent's avatar: the `Agent.avatar` glyph when it's a short emoji/text,
/// otherwise a coloured initial. (URL avatars fall back to the initial for
/// now — the field is usually an emoji in this system.)
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    required this.name,
    this.avatar,
    this.radius = 20,
  });

  final String name;
  final String? avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = avatar?.trim();
    final isGlyph =
        a != null && a.isNotEmpty && a.length <= 4 && !a.startsWith('http');
    final initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary.withValues(alpha: 0.16),
      child: isGlyph
          ? Text(a, style: TextStyle(fontSize: radius))
          : Text(
              initial,
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.8,
              ),
            ),
    );
  }
}
