import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// How much a file edit changed, at a glance.
///
/// The one number a reviewer wants before deciding whether to read the diff:
/// "+3 −1" is a tweak, "+412 −0" is a new file, "+2 −380" needs looking at.
/// Hiding that behind a tap means the interesting edit reads exactly like the
/// trivial one in a list of twenty.
class DiffStat {
  const DiffStat({required this.added, required this.removed});

  final int added;
  final int removed;

  bool get isEmpty => added == 0 && removed == 0;

  /// Counts `+`/`-` lines in a unified diff, skipping the `+++`/`---` headers.
  static DiffStat parse(String diff) {
    var added = 0;
    var removed = 0;
    for (final line in diff.split('\n')) {
      if (line.startsWith('+++') || line.startsWith('---')) continue;
      if (line.startsWith('+')) {
        added++;
      } else if (line.startsWith('-')) {
        removed++;
      }
    }
    return DiffStat(added: added, removed: removed);
  }
}

/// The `+12 −3` badge.
class DiffStatChip extends StatelessWidget {
  const DiffStatChip({super.key, required this.stat});

  final DiffStat stat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppTheme.mono(fontSize: 11, height: 1.2);
    if (stat.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stat.added > 0)
          Text('+${stat.added}',
              style: style.copyWith(
                  color: cs.primary, fontWeight: FontWeight.w700)),
        if (stat.added > 0 && stat.removed > 0) const SizedBox(width: 6),
        if (stat.removed > 0)
          // A true minus sign, not a hyphen: it sits at the same optical
          // height as the plus, which matters when the two are side by side.
          Text('−${stat.removed}',
              style: style.copyWith(
                  color: cs.error, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// A unified diff, coloured.
///
/// Every surface that shows an agent's file edits renders it the same way —
/// the Console's Ask tab and the chat transcript had two copies of this, which
/// is two chances for a `+` line to be green in one place and grey in the
/// other for the same edit.
class DiffBody extends StatelessWidget {
  const DiffBody(this.diff, {super.key, this.fontSize = 11.5});

  final String diff;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mono = AppTheme.mono(fontSize: fontSize, height: 1.4);

    return SelectableText.rich(
      TextSpan(
        children: [
          for (final line in diff.split('\n'))
            TextSpan(
              text: '$line\n',
              style: switch (line.isEmpty ? ' ' : line[0]) {
                '+' =>
                  mono.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                '-' => mono.copyWith(color: cs.error),
                '@' => mono.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                _ => mono.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.85)),
              },
            ),
        ],
      ),
    );
  }
}
