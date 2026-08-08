import 'package:cyberneurova_mobile/shared/time/record_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/memory/data/models/memory_model.dart';
import 'package:cyberneurova_mobile/features/memory/presentation/providers/memory_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(memoryListProvider);
    final l = AppL10n.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l.memory),
        actions: [
          memories.maybeWhen(
            data: (snap) => snap.memories.isEmpty
                ? const SizedBox()
                : IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Clear all',
                    onPressed: () => _confirmClearAll(context, ref),
                  ),
            orElse: () => const SizedBox(),
          ),
        ],
      ),
      body: MaxWidthContent(child: memories.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => const CnShimmer(
              width: double.infinity, height: 80, radius: 12),
        ),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.refresh(memoryListProvider.future),
        ),
        data: (snap) => snap.memories.isEmpty
            ? _EmptyMemory()
            : RefreshIndicator(
                onRefresh: () => ref.refresh(memoryListProvider.future),
                child: CustomScrollView(
                  slivers: [
                    if (snap.tracker != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        sliver: SliverToBoxAdapter(
                          child: _TrackerCard(
                            tracker: snap.tracker!,
                            count: snap.count,
                            limit: snap.limit,
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _GroupedMemoryList(memories: snap.memories),
                    ),
                  ],
                ),
              ),
      )),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${l.delete} ${l.memory}?'),
        content: Text(l.cannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              l.delete,
              style: TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(memoryListProvider.notifier).clearAll();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userMessageFor(context, e))),
          );
        }
      }
    }
  }
}

/// Localized category metadata used by the tracker and breakdown widgets.
/// Defined at top-level so both `_TrackerCard` and `_CategoryBreakdown` can
/// reach it without coupling them.
///
/// The purples/amber are a fixed CATEGORICAL data-viz palette (no ColorScheme
/// slot maps to "category hue"), chosen to read on both the dark navy and the
/// light gray canvas — deliberate literals, not a theming miss. `context`
/// (neutral) does map cleanly to a token, so it follows the theme.
List<({String key, String label, Color color})> _categoriesFor(
    AppL10n l, ColorScheme cs) =>
    [
      (key: 'preference', label: l.categoryPreferences, color: const Color(0xFF7C5DDB)),
      (key: 'fact', label: l.categoryFacts, color: const Color(0xFFB57BDD)),
      (key: 'project', label: l.categoryProjects, color: const Color(0xFFFFB347)),
      (key: 'pattern', label: l.categoryPatterns, color: const Color(0xFF8B5CF6)),
      (key: 'context', label: l.categoryContext, color: cs.onSurfaceVariant),
    ];

/// Tracker summary above the list. Count chip with capacity meter,
/// category breakdown bar, average importance, last-updated relative time.
class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    required this.tracker,
    required this.count,
    required this.limit,
  });

  final MemoryTracker tracker;
  final int count;
  final int limit;


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = limit > 0 ? (count / limit).clamp(0.0, 1.0) : 0.0;
    final atCapacityWarn = pct >= 0.95;
    final amber = pct >= 0.80 && pct < 0.95;
    final progressColor = atCapacityWarn
        ? cs.error
        : amber
            // Warning amber — no "warning" slot exists in the ColorScheme;
            // this literal reads on both the navy and light canvases.
            ? const Color(0xFFFFB347)
            : cs.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.psychology_alt_outlined,
                    size: 18, color: progressColor),
              ),
              const SizedBox(width: 10),
              Text(
                AppL10n.of(context).memory,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '$count / $limit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: progressColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Capacity bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: cs.outline,
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
          const SizedBox(height: 14),

          // Category breakdown bar
          _CategoryBreakdown(
            counts: tracker.categoryCounts,
            total: count > 0 ? count : 1,
          ),
          const SizedBox(height: 14),

          // Meta row: average importance + last updated
          Row(
            children: [
              Icon(Icons.bolt_outlined,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'Avg importance ${tracker.averageImportance.toStringAsFixed(1)} / 5',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              if (tracker.lastExtractedAt != null) ...[
                Icon(Icons.history_rounded,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Updated ${_relative(tracker.lastExtractedAt!)}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _relative(DateTime dt) => recordTime(dt);
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.counts, required this.total});
  final Map<String, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cats = _categoriesFor(AppL10n.of(context), cs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stacked-bar visualisation
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                for (final c in cats)
                  Expanded(
                    flex: (counts[c.key] ?? 0).clamp(0, total),
                    child: Container(color: c.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Legend with counts
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final c in cats)
              if ((counts[c.key] ?? 0) > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.color,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${c.label} ${counts[c.key]}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

class _GroupedMemoryList extends ConsumerWidget {
  const _GroupedMemoryList({required this.memories});
  final List<MemoryModel> memories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by category
    final groups = <String, List<MemoryModel>>{};
    for (final m in memories) {
      groups.putIfAbsent(m.category, () => []).add(m);
    }
    // Sort within each group by importance desc
    for (final list in groups.values) {
      list.sort((a, b) => b.importance.compareTo(a.importance));
    }

    // Stable order of categories
    const categoryOrder = ['preference', 'fact', 'project', 'pattern', 'context'];
    final orderedCategories = [
      ...categoryOrder.where(groups.containsKey),
      ...groups.keys.where((k) => !categoryOrder.contains(k)),
    ];

    // shrinkWrap + no physics: this sits inside a SliverToBoxAdapter, which
    // hands its child UNBOUNDED height. A plain ListView there either throws
    // "Vertical viewport was given unbounded height" or lays out to nothing,
    // and the second is what a user sees — a Memory screen that renders
    // completely blank, with no list, no empty state and no error to explain
    // it. The outer CustomScrollView already does the scrolling.
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: orderedCategories.length,
      itemBuilder: (_, i) {
        final cat = orderedCategories[i];
        final items = groups[cat]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i > 0) const SizedBox(height: 24),
            _CategoryHeader(category: cat, count: items.length),
            const SizedBox(height: 8),
            ...items.asMap().entries.map((entry) {
              final idx = entry.key;
              final m = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemoryTile(memory: m)
                    .animate(delay: Duration(milliseconds: idx * 30))
                    .fadeIn(duration: 200.ms),
              );
            }),
          ],
        );
      },
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category, required this.count});
  final String category;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);
    // `project` amber / `pattern` violet are part of the fixed categorical
    // palette (see `_categoriesFor`) — no ColorScheme slot exists for them.
    final (label, icon, color) = switch (category) {
      'preference' => (l.categoryPreferences, Icons.tune_rounded, cs.primary),
      'fact' => (l.categoryFacts, Icons.school_outlined, cs.secondary),
      'project' =>
        (l.categoryProjects, Icons.folder_outlined, const Color(0xFFFFB347)),
      'pattern' =>
        (l.categoryPatterns, Icons.timeline_rounded, const Color(0xFF8B5CF6)),
      'context' => (l.categoryContext, Icons.notes_rounded, cs.onSurfaceVariant),
      _ => (category, Icons.tag_rounded, cs.onSurfaceVariant),
    };

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MemoryTile extends ConsumerWidget {
  const _MemoryTile({required this.memory});
  final MemoryModel memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) async {
        try {
          await ref.read(memoryListProvider.notifier).deleteOne(memory.id);
        } catch (_) {
          // The provider reverts state (the row reappears) on failure; swallow
          // so a failed delete doesn't surface as an unhandled async error.
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImportanceDots(level: memory.importance),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                memory.content,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportanceDots extends StatelessWidget {
  const _ImportanceDots({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 8,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          final active = i < level;
          return Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.3),
            ),
          );
        }).reversed.toList(),
      ),
    );
  }
}

class _EmptyMemory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_alt_outlined,
                    size: 64, color: cs.primary.withValues(alpha: 0.3))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    begin: 1.0,
                    end: 1.08,
                    duration: 2000.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: 16),
            Text(
              l.memoryEmptyTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.memoryEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
