import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cyberneurova_mobile/core/routing/safe_pop.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/sources_sheet.dart';
import 'package:cyberneurova_mobile/features/research/data/models/research_models.dart';
import 'package:cyberneurova_mobile/features/research/presentation/providers/research_provider.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// One research session — its queries in a timeline with sources collapsed
/// behind a chip that opens the standard SourcesSheet on tap.
class ResearchDetailScreen extends ConsumerWidget {
  const ResearchDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(researchDetailProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.popOr('research'),
        ),
        title: detail.when(
          loading: () => const CnShimmer(width: 140, height: 14, radius: 4),
          error: (_, __) => const Text('Research'),
          data: (d) => Text(
            d.session.title.isEmpty ? 'Research' : d.session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const _DetailShimmer(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.refresh(researchDetailProvider(sessionId).future),
        ),
        data: (d) => _Body(detail: d),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete research session?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(researchSessionsProvider.notifier).delete(sessionId);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessageFor(context, e))),
        );
      }
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});
  final ResearchDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (detail.queries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No queries in this session yet.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      itemCount: detail.queries.length,
      itemBuilder: (_, i) => _QueryCard(
        query: detail.queries[i],
        isFirst: i == 0,
      ),
    );
  }
}

class _QueryCard extends StatelessWidget {
  const _QueryCard({required this.query, required this.isFirst});
  final ResearchQuery query;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt — small label
          Row(
            children: [
              Icon(Icons.arrow_circle_up_rounded,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'QUERY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (query.createdAt != null) ...[
                const Spacer(),
                Text(
                  _relative(query.createdAt!),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            query.prompt,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Response — markdown
          if (query.response.isNotEmpty)
            MarkdownBody(
              data: query.response,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                p: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                code: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF7EDCB4),
                ),
                codeblockDecoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outline),
                ),
              ),
            ),

          // Sources chip
          if (query.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            SourcesChip(
              sources: [
                for (final s in query.sources)
                  SourceItem(
                    title: s.title ?? s.url,
                    url: s.url,
                    faviconUrl: s.favicon,
                    snippet: s.snippet,
                  ),
              ],
            ),
          ],

          const SizedBox(height: 6),
          const Divider(height: 24),
        ],
      ),
    );
  }

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _DetailShimmer extends StatelessWidget {
  const _DetailShimmer();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CnShimmer(width: 100, height: 10, radius: 5),
          SizedBox(height: 8),
          CnShimmer(width: double.infinity, height: 18, radius: 6),
          SizedBox(height: 14),
          CnShimmer(width: double.infinity, height: 80, radius: 12),
          SizedBox(height: 24),
          CnShimmer(width: 100, height: 10, radius: 5),
          SizedBox(height: 8),
          CnShimmer(width: 280, height: 18, radius: 6),
          SizedBox(height: 14),
          CnShimmer(width: double.infinity, height: 120, radius: 12),
        ],
      ),
    );
  }
}
