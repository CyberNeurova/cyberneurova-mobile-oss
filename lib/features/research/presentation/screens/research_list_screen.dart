import 'package:cyberneurova_mobile/shared/time/record_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/research/data/models/research_models.dart';
import 'package:cyberneurova_mobile/features/research/presentation/providers/research_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';
import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/surface_capabilities_sheet.dart';

/// Top-level Research surface — list of sessions with a category filter row.
/// "New research" CTA navigates into the standard new-chat flow.
class ResearchListScreen extends ConsumerWidget {
  const ResearchListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(researchSessionsProvider);
    final activeCategory = ref.watch(researchCategoryProvider);
    final cs = Theme.of(context).colorScheme;

    // Research a user starts TODAY is a chat tagged `section: "research"` —
    // that is what the New research button creates. This list only ever read
    // `GET /research/sessions`, a different store, so a session created by
    // this screen's own main action could never appear on it. Verified on
    // device 2026-08-05: two research sessions run back to back, neither in
    // the list, which still showed one row from June.
    //
    // Both are shown rather than swapping one for the other: the old store is
    // still the only home for anything created before this, and losing it from
    // view would look exactly like the bug being fixed.
    //
    // Only under "All" — the category chips filter the old store's own
    // `category` field, which a chat does not have, so showing chats under
    // "CVE" would quietly make the filter a lie.
    final researchChats = activeCategory == null
        ? (ref.watch(chatListProvider).valueOrNull ?? const [])
            .where((c) => c.section == AppConstants.sectionResearch)
            .toList()
        : const [];

    return Scaffold(
      // Sidebar reachable from here — tap the menu to jump to another section
      // instead of having to go back to a chat first.
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar — menu (reopens sidebar) + serif title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.menu_rounded, size: 24),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppL10n.of(context).research,
                    // serifDisplay defaults to the dark palette's near-white;
                    // pass the live scheme's ink so light mode reads.
                    style: AppTheme.serifDisplay(size: 22, color: cs.onSurface),
                  ),
                  const Spacer(),
                  const SurfaceCapabilitiesAction(
                      surface: AgentSurface.research),
                ],
              ),
            ),

            // Category chips
            _CategoryRow(
              active: activeCategory,
              onSelected: (c) {
                HapticFeedback.selectionClick();
                ref.read(researchCategoryProvider.notifier).state = c;
              },
            ),

            // Session list
            Expanded(
              child: MaxWidthContent(child: sessions.when(
                loading: () => const _ListShimmer(),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () =>
                      ref.refresh(researchSessionsProvider.future),
                ),
                data: (list) => list.isEmpty && researchChats.isEmpty
                    ? const _EmptyResearch()
                    : RefreshIndicator(
                        color: cs.primary,
                        onRefresh: () => ref.refresh(
                            researchSessionsProvider.future),
                        // Fetch the next page near the bottom. `loadMore` was defined,
                        // guarded against re-entrancy, and called by NOTHING — so the list
                        // stopped at one page of AppConstants.defaultPageLimit and every
                        // older row was unreachable. Same fault as the chat drawer.
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            final m = n.metrics;
                            if (m.axis == Axis.vertical &&
                                m.pixels >= m.maxScrollExtent - 400) {
                              ref.read(researchSessionsProvider.notifier).loadMore();
                            }
                            return false;
                          },
                          child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                              16, 8, 16, 100),
                          children: [
                            // No l10n key exists for a section label —
                            // matches the hardcoded-string convention used
                            // in settings.
                            const _SectionHeader(label: 'Sessions'),
                            if (researchChats.isNotEmpty)
                              _GroupCard(
                                children: [
                                  for (var i = 0;
                                      i < researchChats.length;
                                      i++) ...[
                                    if (i > 0) const _Sep(),
                                    _ResearchChatTile(chat: researchChats[i]),
                                  ],
                                ],
                              ).animate().fadeIn(duration: 200.ms),
                            if (researchChats.isNotEmpty && list.isNotEmpty)
                              const SizedBox(height: 16),
                            if (list.isNotEmpty)
                              _GroupCard(
                                children: [
                                  for (var i = 0; i < list.length; i++) ...[
                                    if (i > 0) const _Sep(),
                                    _SessionTile(session: list[i]),
                                  ],
                                ],
                              ).animate().fadeIn(duration: 200.ms),
                          ],
                          ),
                        ),
                      ),
              )),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newResearch(context, ref),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(AppL10n.of(context).newResearch),
      ),
    );
  }
}

/// Shared "new research" CTA — used by the FAB and the empty state.
///
/// This was a "coming soon" snackbar, written when there was genuinely nowhere
/// for a research turn to go: no streaming research endpoint, and `section` did
/// not survive `POST /chat`. Saying so was the honest choice at the time.
///
/// All three parts of that are now false. `section: "research"` persists,
/// the deviceContext gate is open to it, and [AgentSurface.research] maps the
/// section onto the run protocol — so a research chat already gets the
/// research focus block and the device tools, through exactly the same path
/// Ask uses. The main action of the app's primary entry point should not stay
/// a dead end once the thing it was waiting for has shipped.
Future<void> _newResearch(BuildContext context, WidgetRef ref) async {
  HapticFeedback.mediumImpact();
  try {
    final chat = await ref
        .read(chatListProvider.notifier)
        .createChat(section: AppConstants.sectionResearch);
    if (!context.mounted) return;
    context.pushNamed('chat-detail', pathParameters: {'id': chat.id});
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userMessageFor(context, e)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─── Grouped card system (same visual language as settings_screen) ──────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 0.5, indent: 16, endIndent: 16);
}

// ─── Category row ────────────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.active, required this.onSelected});
  final String? active;
  final void Function(String?) onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final categories = [
      (key: null, label: l.researchAll, icon: Icons.all_inclusive_rounded),
      (key: 'cve', label: l.researchCVE, icon: Icons.bug_report_outlined),
      (key: 'exploit', label: l.researchExploit, icon: Icons.security_outlined),
      (key: 'bugbounty', label: l.researchBugBounty, icon: Icons.account_balance_wallet_outlined),
      (key: 'malware', label: l.researchMalware, icon: Icons.coronavirus_outlined),
      (key: 'pentest', label: l.researchPentest, icon: Icons.terminal_rounded),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = categories[i];
          final selected = c.key == active;
          return GestureDetector(
            onTap: () => onSelected(c.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                // Selected chip inverts: ink-colored pill with surface-colored
                // label (near-white pill in dark, navy pill in light).
                color: selected ? cs.onSurface : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? cs.onSurface : cs.outline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    c.icon,
                    size: 13,
                    color: selected ? cs.surface : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.surface : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Session tile ────────────────────────────────────────────────────────────

/// A research session that is a chat — everything started since the New
/// research button began creating one.
///
/// Deliberately not a [Dismissible]: [_SessionTile] deletes through
/// `researchSessionsProvider`, which only knows the old store and would report
/// success while leaving the row's chat untouched. Deleting a chat belongs to
/// the chat list, and offering a swipe that silently does nothing is worse
/// than offering none.
class _ResearchChatTile extends StatelessWidget {
  const _ResearchChatTile({required this.chat});
  final ChatModel chat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        context.pushNamed('chat-detail', pathParameters: {'id': chat.id});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.science_outlined, size: 18, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sessionDisplayTitle(chat.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Time, not a message count. `messageCount` comes from the
                    // server, agent-run turns are never written there (outbox
                    // 054), and every one of these rows therefore reported
                    // "0 messages" under a session with a full conversation in
                    // it. A number that is always wrong is worse than no
                    // number.
                    relativeResearchTime(chat.updatedAt ?? chat.createdAt),
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final ResearchSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final categoryIcon = switch (session.category) {
      'cve' => Icons.bug_report_outlined,
      'exploit' => Icons.security_outlined,
      'bugbounty' => Icons.account_balance_wallet_outlined,
      'malware' => Icons.coronavirus_outlined,
      'pentest' => Icons.terminal_rounded,
      _ => Icons.science_outlined,
    };

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 16),
        child: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        final l = AppL10n.of(context);
        return await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: Text('${l.delete} ${l.research}?'),
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
                      style: TextStyle(
                          color: Theme.of(dialogCtx).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        try {
          await ref.read(researchSessionsProvider.notifier).delete(session.id);
        } catch (_) {
          // The provider reverts state (the row reappears) on failure; swallow
          // so a failed delete doesn't surface as an unhandled async error.
        }
      },
      child: GestureDetector(
        // Opaque GestureDetector instead of InkWell: the Dismissible's drag
        // recogniser was swallowing the InkWell's tap (tap did nothing).
        // Opaque hit-testing + a plain tap recogniser reliably wins for a
        // tap — so this row keeps a GestureDetector (no ripple) as a known
        // exception to the grouped-card InkWell rule.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          context.pushNamed(
            'research-detail',
            pathParameters: {'id': session.id},
          );
        },
        child: Padding(
          // 16/12 padding + 36px leading → ≥48px rows, on the 4/8 grid.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(categoryIcon,
                    size: 18, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // `isEmpty` was not enough — a punctuation-only query
                      // ("??") is a non-empty title that names nothing.
                      isUnusableTitle(session.title)
                          ? 'Untitled research'
                          : session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.queryCount} ${session.queryCount == 1 ? "query" : "queries"} · ${_relative(session.lastQueryAt ?? session.createdAt)}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _relative(DateTime? dt) => relativeResearchTime(dt);
}

/// Shared by both row types so a chat-backed session and an old-store session
/// never describe the same age two different ways.
String relativeResearchTime(DateTime? dt) =>
    recordTime(dt, ifNull: 'recently');

// ─── Shimmer + empty ─────────────────────────────────────────────────────────

class _ListShimmer extends StatelessWidget {
  const _ListShimmer();
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: CnShimmer(width: 72, height: 12, radius: 6),
        ),
        _GroupCard(
          children: [
            for (var i = 0; i < 8; i++) ...[
              if (i > 0) const _Sep(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CnShimmer(width: 36, height: 36, radius: 10),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CnShimmer(width: 180, height: 13, radius: 6),
                          SizedBox(height: 6),
                          CnShimmer(width: 100, height: 10, radius: 5),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EmptyResearch extends ConsumerWidget {
  const _EmptyResearch();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined,
                size: 56, color: cs.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(
              l.noResearchYet,
              style: AppTheme.serifDisplay(size: 22, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l.researchEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _newResearch(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(l.newResearch),
            ),
          ],
        ),
      ),
    );
  }
}
