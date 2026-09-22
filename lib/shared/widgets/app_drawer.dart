import 'package:cyberneurova_mobile/features/projects/presentation/screens/projects_screen.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/archived_chats_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_selection_bar.dart';
import 'package:cyberneurova_mobile/features/projects/data/repositories/project_repository.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/providers/projects_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';

/// left drawer (drawer v2, docs/REDESIGN.md "redesign pass").
/// Header = wordmark + avatar/name/tier as one tappable block (→ settings).
/// Body = quiet Recents list (title + relative date) and a divider-separated
/// secondary nav group, all one CustomScrollView. A floating pill bar docked
/// at the bottom safe area carries the three global actions:
/// search pill · settings gear · new chat.
class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  @override
  void initState() {
    super.initState();
    // Auto-clear any stuck multi-selection from a previous drawer open
    // — without this, an accidental long-press in a prior session keeps
    // selection mode active, which hides `_PrimaryNav` (and therefore
    // the "New Chat" button). User-reported as "New Chat button doesn't
    // work at all" because it's literally not visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedChatsProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final user = ref.watch(authProvider).valueOrNull;
    final l = AppL10n.of(context);

    return Drawer(
      width: Responsive.drawerWidth(context),
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      // Inset from the system bars so the curve is actually SEEN.
      //
      // The corners were always rounded — measuring a device screenshot row by
      // row showed the right edge dead straight at x=884 from y=100 to y=2200,
      // because a full-bleed drawer puts its 32dp corners at y<96 and y>2244,
      // i.e. underneath the status bar and the navigation bar. Rounding you
      // cannot see is the same as no rounding.
      //
      // Insetting by the system padding lifts both corners into the visible
      // area and makes the drawer read as a floating panel rather than a slab.
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.viewPaddingOf(context).top,
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        // No BackdropFilter.
        //
        // It defeated the rounded corners: under Impeller a BackdropFilter
        // paints its own backdrop and escapes the enclosing ClipRRect, so the
        // drawer rendered with hard square corners no matter what shape it
        // was given — verified by cropping the corner from a device
        // screenshot.
        //
        // Nothing is lost visually. The gradient below is 94–97% opaque, so
        // the blur was invisible while costing a FULL-HEIGHT backdrop filter
        // every frame — exactly what `glass_surface.dart` warns against
        // ("Never wrap a full-screen widget in one"). Removing it fixes the
        // silhouette and makes the drawer cheaper to paint.
        child: Container(
            decoration: BoxDecoration(
              // Frosted NAVY (on-brand) — the old white-alpha glass read grayish
              // and washed-out on the navy theme.
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context)
                      .colorScheme
                      .surfaceContainer
                      .withValues(alpha: 0.94),
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.97),
                ],
              ),
              border: Border(
                right: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.7),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Selection mode action bar — only shown when one or
                  // more chats are selected. Replaces the top controls to
                  // make the mode obvious (gmail/photos pattern).
                  const _SelectionActionBar(),
                  // Fixed top: a compact search pill (where thumbs expect it).
                  // Hidden in selection mode so the action bar reads as
                  // exclusive.
                  _MaybeSearchBar(l: l, ref: ref),
                  // Everything between the top controls and the account card is
                  // one scroll surface. SlidableAutoCloseBehavior: opening one
                  // row's action pane closes any other open pane, so at most
                  // one pane is ever locked open (scrolling closes it too —
                  // closeOnScroll).
                  Expanded(
                    child: SlidableAutoCloseBehavior(
                      // Fetch the next page as the user nears the bottom.
                      //
                      // `ChatListNotifier.loadMore` existed, was guarded
                      // against re-entrancy, and was called by NOTHING — so the
                      // app fetched exactly one page of
                      // `AppConstants.defaultPageLimit` chats and never another
                      // one. Every conversation older than the twentieth
                      // newest was unreachable on the phone while being right
                      // there on the web.
                      //
                      // A notification listener rather than a ScrollController
                      // because this scroll view has no controller to attach to
                      // and does not need one; the notifier's own guard makes
                      // the repeated calls near the bottom harmless.
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          final m = n.metrics;
                          if (m.axis == Axis.vertical &&
                              m.pixels >= m.maxScrollExtent - 400) {
                            ref.read(chatListProvider.notifier).loadMore();
                          }
                          return false;
                        },
                        child: CustomScrollView(
                        slivers: [
                          // Nav (Projects, Agents, Bot Chat) — compact
                          // icon+label rows, the drawer's navigation, BEFORE
                          // the chat history. Hidden in selection mode.
                          SliverToBoxAdapter(
                            child: _MaybeWorkspace(l: l),
                          ),
                          SliverToBoxAdapter(
                            child: _SectionLabel(label: l.recents),
                          ),
                          // The actual chat list — same scroll surface.
                          const _StaleNotice(),
                          const _RecentsSliver(),
                          // Collapsed "Archived (N)" group under the recents
                          // (device-local archive v1 — see
                          // archived_chats_provider.dart + outbox/034).
                          const SliverToBoxAdapter(child: _ArchivedSection()),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 12)),
                        ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom bar — a compact teal "New chat" pill + a settings
                  // gear (reference pattern). No heavy profile card; identity and
                  // plan live behind the gear, in settings. Hidden while the
                  // selection action bar is up so the mode reads as exclusive.
                  _MaybeBottomBar(l: l, ref: ref, user: user),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Top controls (search + New chat) ───────────────────────────────────────

/// A floating search icon at the top of the drawer (reference pattern) — the
/// search input itself lives on the search screen, so a tap just opens it.
/// Right-aligned so it echoes the reference's top-right search affordance.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.l, required this.ref});
  final AppL10n l;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: [
          const Spacer(),
          _CircleButton(
            icon: Icons.search_rounded,
            tooltip: l.search,
            iconColor: cs.onSurfaceVariant,
            fill: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            onTap: () {
              // Capture the router BEFORE popping the drawer — the drawer's own
              // context is torn down by the pop.
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.pushNamed('chat-search');
            },
          ),
        ],
      ),
    );
  }
}

// ─── Bottom bar (New chat pill + settings gear) ──────────────────────────────

/// A compact teal "New chat" pill next to a settings gear (reference pattern) —
/// the accented action no longer spans the whole drawer, and there is no heavy
/// profile card. Identity and plan live behind the gear, in settings (or
/// login when signed out).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.l, required this.ref, required this.user});
  final AppL10n l;
  final WidgetRef ref;
  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          // New chat — a content-sized teal pill, not a full-width row.
          Material(
            color: cs.primary,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _newChat(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
                    const SizedBox(width: 8),
                    Text(
                      l.newChat,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // Settings gear — identity + plan live here now (login when signed
          // out).
          _CircleButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            iconColor: cs.onSurfaceVariant,
            fill: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.pushNamed(user == null ? 'login' : 'settings');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _newChat(BuildContext context) async {
    // Reuse an existing empty chat when one exists (or create one otherwise) —
    // repeated New Chat taps without sending used to mint a blank server
    // record each time. Capture router + messenger BEFORE Navigator.pop —
    // once the drawer pops, this context starts disposing and goNamed no-ops.
    HapticFeedback.mediumImpact();
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      final chat =
          await ref.read(chatListProvider.notifier).reuseOrCreateEmptyChat();
      router.goNamed('chat-detail', pathParameters: {'id': chat.id});
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.mounted
              ? "Couldn't create chat. ${userMessageFor(context, e)}"
              : "Couldn't create chat."),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

// ─── Workspace (Projects, Agents, Bot Chat) ──────────────────────────────────

/// The drawer's navigation group, above Recents: compact icon + label rows
/// (reference pattern — no header, no wells, no chevrons). Same tap behaviour
/// as before (pop drawer, then push).
class _Workspace extends StatelessWidget {
  const _Workspace({required this.l});
  final AppL10n l;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _WorkspaceNavItem(
          icon: Icons.folder_outlined,
          label: l.projectsTitle,
          onTap: () {
            Navigator.pop(context);
            context.pushNamed('profile-projects');
          },
        ),
        // Media is no longer a drawer destination — the Ask ↔ Imagine switch
        // in the header covers that jump in one tap, which is what it was
        // mostly used for. The generated-media library is reachable from the
        // Imagine surface itself.
        //
        // Research is no longer a top-level peer either: it sits inside
        // Agents alongside Code, so the two agentic workspaces live together
        // and the sidebar stays two destinations deep.
        _WorkspaceNavItem(
          icon: Icons.auto_awesome_outlined,
          label: 'Agents',
          onTap: () {
            Navigator.pop(context);
            context.pushNamed('agents');
          },
        ),
        // Agent Contacts (bot-section) — DM your AI contacts. A peer of Agents:
        // Agents is where the agent runs tools; Contacts is where you talk to
        // them and (P2+) drive a work chat remotely.
        _WorkspaceNavItem(
          icon: Icons.forum_outlined,
          label: 'Bot Chat',
          onTap: () {
            Navigator.pop(context);
            context.pushNamed('bots');
          },
        ),
      ],
    );
  }
}

/// A destination row: plain icon + label, no well and no chevron (the reference
/// density). The whole row is a ≥44px touch target.
class _WorkspaceNavItem extends StatelessWidget {
  const _WorkspaceNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurface),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface,
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

// ─── Section label (matches settings_screen.dart group headers) ─────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

// ─── Recents (sliver so it joins the parent scroll) ──────────────────────────

class _RecentsSliver extends ConsumerWidget {
  const _RecentsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Plain conversations only — Console/Code/Research sessions belong to
    // their own surfaces, not to Recents.
    final chats = ref.watch(plainChatListProvider);
    final l = AppL10n.of(context);

    // Hide empty chats (`messageCount == 0`) AND archived chats in normal
    // browse mode — common chat-app drawers don't show blank conversations, and
    // archived rows live in the collapsed "Archived (N)" group below.
    // Selection mode shows EVERYTHING (blanks + archived) so legacy blanks
    // and archived chats can still be bulk-selected and deleted.
    final isSelectionMode = ref.watch(selectedChatsProvider).isNotEmpty;
    final archived = ref.watch(archivedChatsProvider);

    // Signed out is not a failure. Without this the drawer greeted a brand-new
    // user with "Couldn't load your chats — Missing authorization header" and a
    // Try again button that could never work: an internal HTTP detail dressed
    // up as something broken, in the first thing they open. There is nothing
    // wrong; they simply have no account yet.
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    return chats.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox()),
      // Errors are not silent any more. An empty drawer with no explanation
      // reads as "you have no chats", which is a much worse lie than "we
      // couldn't load them".
      error: (e, __) => SliverToBoxAdapter(
        child: signedIn
            ? _RecentsProblem(
                message: userMessageFor(context, e), onRetry: () {
                ref.invalidate(chatListProvider);
              })
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text(
                  l.chatsWillAppearHere,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13),
                ),
              ),
      ),
      data: (all) {
        final list = isSelectionMode
            ? all
            : [
                for (final c in all)
                  if (c.messageCount != 0 && !archived.contains(c.id)) c
              ];
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text(
                l.chatsWillAppearHere,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13),
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _RecentItem(chat: list[i]),
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}

class _RecentItem extends ConsumerWidget {
  const _RecentItem({required this.chat, this.archived = false});
  final ChatModel chat;

  /// True when this row renders inside the "Archived (N)" group — the
  /// action pane swaps Archive for Unarchive; tap/long-press behave the
  /// same as a normal recents row.
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChatsProvider);
    final isSelectionMode = selected.isNotEmpty;
    final isSelected = selected.contains(chat.id);
    final cs = Theme.of(context).colorScheme;
    final when = _relativeTime(chat.updatedAt ?? chat.createdAt);

    // InkWell restored (the Dismissible era used an opaque GestureDetector
    // because Dismissible's own horizontal drag recogniser swallowed
    // InkWell taps — see research_list_screen.dart's _SessionTile finding).
    // Slidable doesn't have that problem: it only claims the gesture once
    // horizontal movement passes the drag slop, so a plain tap reaches the
    // InkWell reliably and we get the ripple back. Wrapped in a Builder so
    // Slidable.of() can reach this row's controller: when the action pane
    // is locked open, a tap on the row closes the pane instead of
    // navigating (bottom-sheet-scrim semantics).
    final row = Builder(
      builder: (rowCtx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Material(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              final slidable = Slidable.of(rowCtx);
              if (slidable != null && slidable.ratio != 0) {
                slidable.close();
                return;
              }
              HapticFeedback.selectionClick();
              if (isSelectionMode) {
                // Tap toggles when in selection mode — matches Photos /
                // Gmail behavior. Tapping the last selected item exits
                // selection mode automatically (selection becomes empty).
                ref.read(selectedChatsProvider.notifier).toggle(chat.id);
                return;
              }
              Navigator.pop(context);
              // `go` (replace) — selecting a chat from the drawer shouldn't
              // grow a back stack of past chats.
              context.goNamed(
                'chat-detail',
                pathParameters: {'id': chat.id},
              );
            },
            onLongPress: () {
              // Enter selection mode (or add to existing selection).
              HapticFeedback.mediumImpact();
              ref.read(selectedChatsProvider.notifier).toggle(chat.id);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  if (isSelectionMode) ...[
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Title left, relative time right (reference row layout).
                  Expanded(
                    child: Text(
                      chat.title.isEmpty
                          ? AppL10n.of(context).newConversation
                          : chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (when.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      when,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Swipe left → Archive + Delete pane that LOCKS OPEN (DrawerMotion, no
    // dismissible) until an action is tapped, the list scrolls
    // (closeOnScroll default), or another row's pane opens
    // (SlidableAutoCloseBehavior up in the drawer body). Deliberate
    // two-step destructive flow vs the old one-swipe Dismissible.
    // Disabled in selection mode — a horizontal pane would fight the
    // multi-select flow, and bulk delete already covers that mode.
    return Slidable(
      key: ValueKey(chat.id),
      enabled: !isSelectionMode,
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.45,
        children: [
          // Deliberately asymmetric styling (user feedback: the original
          // twin dark-tinted chips were indistinguishable at a glance) —
          // Archive is a quiet neutral card, Delete is SOLID error with
          // onError foreground. iOS-Mail convention: color identifies the
          // destructive action, shape identifies the pair.
          _PaneButton(
            onTap: () => archived
                ? _unarchive(context, ref)
                : _archive(context, ref),
            icon: archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            label: archived ? 'Unarchive' : 'Archive',
            fill: cs.surfaceContainerHighest,
            foreground: cs.onSurfaceVariant,
          ),
          _PaneButton(
            onTap: () => _confirmAndDelete(context, ref),
            icon: Icons.delete_outline,
            label: 'Delete',
            fill: cs.error,
            foreground: cs.onError,
          ),
        ],
      ),
      child: row,
    );
  }

  /// Device-local archive (v1 — see archived_chats_provider.dart +
  /// outbox/034 for the server-side ask). The row leaves Recents via the
  /// provider filter; Undo simply removes the id again.
  // (Pane buttons live in _PaneButton at the bottom of this file.)
  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(archivedChatsProvider.notifier);
    await notifier.archive(chat.id);
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('Archived'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => notifier.unarchive(chat.id),
        ),
      ),
    );
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    await ref.read(archivedChatsProvider.notifier).unarchive(chat.id);
  }

  /// Confirm dialog + single-chat delete, shared by the recents and
  /// archived action panes. (Kept the bool return from the Dismissible
  /// era — harmless, and documents "false = nothing was deleted".)
  Future<bool> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final title = chat.title.isEmpty
        ? AppL10n.of(context).newConversation
        : chat.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "$title"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Delete', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    HapticFeedback.heavyImpact();

    // Capture everything context-derived BEFORE the awaits — the drawer
    // context starts disposing once navigation happens (same pattern as
    // _bulkDelete and the bottom bar's New Chat).
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.of(context);
    final listNotifier = ref.read(chatListProvider.notifier);
    final archivedNotifier = ref.read(archivedChatsProvider.notifier);
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final onThisChat = currentRoute.endsWith('/chats/${chat.id}') ||
        currentRoute.endsWith('/chat/${chat.id}');

    try {
      await listNotifier.deleteChat(chat.id);
    } catch (e) {
      // `messenger` was captured before the await on purpose; `context` may
      // be gone by now, so the detail is only added when it is still valid.
      messenger?.showSnackBar(
        SnackBar(
          content: Text(context.mounted
              ? 'Could not delete chat. ${userMessageFor(context, e)}'
              : 'Could not delete chat.'),
        ),
      );
      return false;
    }
    // Keep the device-local archived set tidy — a deleted chat's id has
    // no business lingering in SharedPreferences.
    await archivedNotifier.unarchive(chat.id);
    messenger?.showSnackBar(const SnackBar(content: Text('Chat deleted')));

    // Deleted the chat the user is currently viewing → land them in a
    // fresh (or reused empty) chat, same as every other post-delete path.
    if (onThisChat) {
      try {
        final fresh = await listNotifier.reuseOrCreateEmptyChat();
        router.goNamed('chat-detail', pathParameters: {'id': fresh.id});
      } catch (_) {
        // reuse/create failed — the chat list is intact; the user can tap
        // any chat from the drawer to recover.
      }
    }
    return true;
  }
}

/// "2h ago"-style short relative date for the recents meta line. Coarse on
/// purpose — the drawer doesn't need minute precision past the first hour.
String _relativeTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final diff = now.difference(t.toLocal());
  if (diff.isNegative) return 'now';
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}

// ─── Archived group (device-local archive v1) ────────────────────────────────

/// Collapsed "Archived (N)" quiet row under Recents. Expands inline to list
/// the archived chats (same row style; slidable pane offers Unarchive +
/// Delete). Renders nothing when no archived chats exist, and hides in
/// selection mode — Recents shows everything unfiltered there, so the group
/// would duplicate rows.
///
/// N counts the *intersection* of the archived-id set with the live chat
/// list, so stale ids (chat deleted elsewhere) never inflate the count.
class _ArchivedSection extends ConsumerStatefulWidget {
  const _ArchivedSection();

  @override
  ConsumerState<_ArchivedSection> createState() => _ArchivedSectionState();
}

class _ArchivedSectionState extends ConsumerState<_ArchivedSection> {
  // Collapsed on every drawer open (state dies with the drawer route) —
  // archived chats are deliberately out of the way.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = ref.watch(selectedChatsProvider).isNotEmpty;
    if (isSelectionMode) return const SizedBox.shrink();

    final archivedIds = ref.watch(archivedChatsProvider);
    // Plain-only, so the count matches the rows this section renders.
    final all =
        ref.watch(plainChatListProvider).valueOrNull ?? const <ChatModel>[];
    final archivedChats = [
      for (final c in all)
        if (archivedIds.contains(c.id)) c
    ];
    if (archivedChats.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quiet toggle row — 18px icon, 14px onSurfaceVariant text,
        // ≥44px target.
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.archive_outlined,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Archived (${archivedChats.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            // Match _RecentsSliver's SliverPadding so archived rows align
            // with the recents rows above.
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in archivedChats)
                  _RecentItem(chat: c, archived: true),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Selection mode: action bar + visibility helpers ────────────────────────

/// Fixed top search pill, hidden in selection mode so the action bar reads as
/// exclusive.
class _MaybeSearchBar extends ConsumerWidget {
  const _MaybeSearchBar({required this.l, required this.ref});
  final AppL10n l;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final hidden = wRef.watch(selectedChatsProvider).isNotEmpty;
    return hidden ? const SizedBox.shrink() : _SearchBar(l: l, ref: ref);
  }
}

/// Bottom bar (New chat pill + gear), hidden in selection mode — keep the
/// visual focus on the selected chats and the action bar.
class _MaybeBottomBar extends ConsumerWidget {
  const _MaybeBottomBar({
    required this.l,
    required this.ref,
    required this.user,
  });
  final AppL10n l;
  final WidgetRef ref;
  final dynamic user;
  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final hidden = wRef.watch(selectedChatsProvider).isNotEmpty;
    return hidden
        ? const SizedBox.shrink()
        : _BottomBar(l: l, ref: ref, user: user);
  }
}

/// Hidden in selection mode for the same reason as `_MaybeBottomBar` — keep
/// the visual focus on the selected chats and the action bar.
class _MaybeWorkspace extends ConsumerWidget {
  const _MaybeWorkspace({required this.l});
  final AppL10n l;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(selectedChatsProvider).isNotEmpty;
    return hidden ? const SizedBox.shrink() : _Workspace(l: l);
  }
}

/// Top action bar that takes over the drawer header when one or more chats
/// are selected. Delegates to the shared [ChatSelectionActionBar] so the
/// drawer, search screen and archived screen all offer the same actions —
/// the drawer is just the only one that can assign chats to a project.
class _SelectionActionBar extends ConsumerWidget {
  const _SelectionActionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedChatsProvider);
    final chats = ref.watch(plainChatListProvider).valueOrNull ?? const [];
    return ChatSelectionActionBar(
      // Scope for "Select all": everything the drawer actually lists.
      visibleChatIds: [
        for (final c in chats)
          if (!archived.contains(c.id)) c.id,
      ],
      onAddToProject: (ids) => _bulkAddToProject(context, ref, ids),
    );
  }
}

Future<void> _bulkAddToProject(
  BuildContext context,
  WidgetRef ref,
  Set<String> ids,
) async {
  // Chat-team's inbox/019 extended POST /projects/<id>/chats to accept
  // an array `chatIds: [...]`. We open a project picker; on tap, fire
  // the batch endpoint once and report the result.
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => _BulkProjectPickerSheet(chatIds: ids),
  );
}

class _BulkProjectPickerSheet extends ConsumerWidget {
  const _BulkProjectPickerSheet({required this.chatIds});
  final Set<String> chatIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final projects = ref.watch(projectsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add ${chatIds.length} '
              '${chatIds.length == 1 ? "chat" : "chats"} to…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            projects.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text("Couldn't load projects",
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text('No projects yet',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            // Open the projects management screen so the
                            // user can create one; selection state stays
                            // intact (the drawer's selectedChatsProvider
                            // is independent of which screen is active).
                            // Caller's responsibility to navigate via
                            // GoRouter from a context up the tree.
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Create a project first'),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in list)
                      ListTile(
                        // Third place this had to be learned: the server
                        // stores icon NAMES, so this sheet listed every
                        // project as "folder <name>".
                        leading: Text(projectGlyph(p.icon),
                            style: const TextStyle(fontSize: 22)),
                        title: Text(p.name,
                            style: TextStyle(color: cs.onSurface)),
                        onTap: () => _assign(context, ref, p.id, p.name),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    String projectId,
    String projectName,
  ) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await ref
          .read(projectRepositoryProvider)
          .addChatsToProject(projectId, chatIds.toList());
      ref.read(selectedChatsProvider.notifier).clear();
      if (!context.mounted) return;
      Navigator.pop(context); // close picker
      final failedCount = result.failedIds.length;
      messenger?.showSnackBar(
        SnackBar(
          // "Added 0 chats" is technically true and reads like success.
          // Adding nothing is a failure from where the user is standing.
          content: Text(assignOutcome(
              added: result.added,
              failed: failedCount,
              projectName: projectName)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content:
              Text("Couldn't add to project. ${userMessageFor(context, e)}"),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ─── Circular icon button (shared helper) ────────────────────────────────────

/// 48px circular icon button (≥44px target). Used for the account card's
/// inline settings gear; pass a transparent fill for a bare look.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.fill,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final Color fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 21, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// Slide-pane action button. CustomSlidableAction with our own card child so
/// the two actions render as visually distinct separated buttons (3px gutter)
/// instead of flutter_slidable's flush twin chips.
class _PaneButton extends StatelessWidget {
  const _PaneButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.fill,
    required this.foreground,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color fill;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return CustomSlidableAction(
      onPressed: (_) => onTap(),
      // Transparent shell — the padded Container below is the visible card.
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Told when the drawer is showing a saved copy rather than a live list.
class _StaleNotice extends ConsumerWidget {
  const _StaleNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(chatListIsStaleProvider)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Showing saved chats',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(chatListProvider),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the list could not be loaded AND there was no cache to fall
/// back to — the only case where the drawer genuinely has nothing.
class _RecentsProblem extends StatelessWidget {
  const _RecentsProblem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't load your chats",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          // AppException subclasses render a clean human sentence from
          // toString(), so this is safe to show directly.
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try again', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}


/// What to tell the user after an add-to-project.
///
/// "Added 0 chats" is technically true and reads like success — that is what
/// the sheet said when the server accepted the request and stored nothing
/// (device, 2026-08-05). From where the user is standing, adding nothing is a
/// failure and should say so.
String assignOutcome({
  required int added,
  required int failed,
  required String projectName,
}) {
  if (added == 0) {
    return failed == 0
        ? 'Nothing was added to "$projectName" — the server accepted the '
            'request but saved no chats.'
        : "Couldn't add to \"$projectName\".";
  }
  final noun = added == 1 ? 'chat' : 'chats';
  return failed == 0
      ? 'Added $added $noun to "$projectName"'
      : 'Added $added $noun; $failed failed';
}
