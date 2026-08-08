import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_backend.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/research/presentation/providers/research_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/core/agent/device/surface_capabilities.dart';

/// Agents — the hub for the two agentic workspaces, Research and Code.
///
/// The drawer used to list Projects, Media and Research as three flat peers,
/// which buried Research and gave Code nowhere to live. Grouping the agentic
/// surfaces behind one destination keeps the sidebar short and gives both
/// workspaces room to grow their own shape (sessions, working directories,
/// long-running task state).
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final research = ref.watch(researchSessionsProvider).valueOrNull;
    final chats = ref.watch(chatListProvider).valueOrNull;
    // Count what the Research list actually shows, which is BOTH stores: the
    // legacy `/research/sessions` records and the chats tagged
    // `section: "research"` that the New research button creates.
    //
    // This card counted only the legacy store, so after the list was fixed to
    // show both it read "1 session" above a list of three. A count that
    // disagrees with the screen it leads to is the same defect as the project
    // chatCount, and this one was self-inflicted.
    final researchCount = (research?.length ?? 0) +
        (chats
                ?.where((c) => c.section == AppConstants.sectionResearch)
                .length ??
            0);
    final codeCount =
        chats?.where((c) => c.section == AppConstants.sectionCode).length;
    final shellCount =
        chats?.where((c) => c.section == AppConstants.sectionShell).length;

    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                    'Agents',
                    style: AppTheme.serifDisplay(size: 22, color: cs.onSurface),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  MaxWidthContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Workspaces where the agent runs tools, keeps its own '
                          'history, and works across many turns.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _SetupPrompt(),
                        _WorkspaceCard(
                          icon: Icons.science_outlined,
                          title: AgentSurface.research.title,
                          // One description, used by the card, the sheet and
                          // the model's prompt. Three copies drift, and the
                          // one the model reads drifts silently.
                          blurb: AgentSurface.research.summary,
                          count: (research == null && chats == null)
                              ? null
                              : researchCount,
                          countLabel: 'session',
                          onTap: () => context.pushNamed('research'),
                        ).animate().fadeIn(duration: 250.ms).slideY(
                            begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                        if (AgentSurface.code.isAvailableHere) ...[
                        const SizedBox(height: 12),
                        _WorkspaceCard(
                          icon: Icons.terminal_rounded,
                          title: AgentSurface.code.title,
                          blurb: AgentSurface.code.summary,
                          count: codeCount,
                          countLabel: 'session',
                          onTap: () => context.pushNamed('code'),
                        ).animate(delay: 70.ms).fadeIn(duration: 250.ms).slideY(
                            begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                        ],
                        if (AgentSurface.console.isAvailableHere) ...[
                        const SizedBox(height: 12),
                        _WorkspaceCard(
                          // Distinct from Code's terminal glyph: the Console
                          // is a live session you drive, not a codebase you
                          // edit.
                          icon: Icons.data_object_rounded,
                          title: AgentSurface.console.title,
                          blurb: AgentSurface.console.summary,
                          count: shellCount,
                          countLabel: 'session',
                          onTap: () => context.pushNamed('shell'),
                        )
                            .animate(delay: 140.ms)
                            .fadeIn(duration: 250.ms)
                            .slideY(
                                begin: 0.06,
                                end: 0,
                                curve: Curves.easeOutCubic),
                        ],
                        // The device surfaces are Android-only — a PTY inside
                        // a PRoot'd rootfs needs to execute a binary the app
                        // unpacked, which iOS does not allow any app to do.
                        // Saying so once beats three cards that cannot keep
                        // the promises printed on them.
                        if (!AgentSurface.console.isAvailableHere)
                          const _DeviceSurfacesUnavailable(),
                        const SizedBox(height: 22),
                        if (AgentSurface.console.isAvailableHere)
                          const _EnvironmentRow(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The environment all three workspaces share.
///
/// Placed on the hub rather than inside Console because the distro installed
/// here is what Code and Research run in too — it stopped being a Console
/// setting the moment every agent surface got device tools. It also answers
/// the question people actually arrive with ("what is my agent running on?")
/// without making them open a session to find out.
/// First-run call to action: install a Linux distribution.
///
/// Shown only when it would actually do something — the build can run one
/// (the exec probe passed) and none is installed yet. Deliberately NOT a
/// forced redirect into setup on first visit: on a Play build there is
/// nothing to install, so that page would be a dead end, and even where it
/// works, hijacking someone who tapped Agents to open a session is hostile.
/// A card they can act on or scroll past says the same thing without taking
/// the decision away.
class _SetupPrompt extends ConsumerWidget {
  const _SetupPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canInstall = ref.watch(canInstallDistrosProvider).valueOrNull;
    final backend = ref.watch(shellBackendProvider);
    final alreadyLinux = backend is ProotShellBackend;
    if (canInstall != true || alreadyLinux) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set up your environment',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Install a Linux distribution once and all three workspaces run '
            'in it — real package managers, and the tools you install stay '
            'put. Everything runs on this device.',
            style: TextStyle(
                fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => context.pushNamed('agent-environment'),
              child: const Text('Choose a distribution'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of Console and Code where the device cannot back them.
///
/// Not an error and not a "coming soon": the surfaces run a PTY inside a
/// PRoot'd Linux rootfs, which needs the app to execute a binary it unpacked
/// itself. iOS does not allow that to any app, so there is no later version
/// where this appears. Saying that plainly is better than a card the user taps
/// into a terminal that can never start.
class _DeviceSurfacesUnavailable extends StatelessWidget {
  const _DeviceSurfacesUnavailable();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phonelink_off_rounded,
              size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Console and Code need a Linux shell on the device, which iOS '
              'does not allow an app to start. Research works here — it uses '
              'your connection, not a shell.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _EnvironmentRow extends ConsumerWidget {
  const _EnvironmentRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final backend = ref.watch(shellBackendProvider);
    // Tri-state: unknown must not claim either answer while the exec probe
    // is still running.
    final canInstall = ref.watch(canInstallDistrosProvider).valueOrNull;

    final subtitle = switch ((backend, canInstall)) {
      (null, _) => 'Checking…',
      (final b?, true) when b is ProotShellBackend => b.label,
      (_, true) => 'Android shell · install Linux for a package manager',
      (_, false) => 'Android shell · PRoot runtime missing',
      _ => 'Android shell',
    };

    return InkWell(
      onTap: () => context.pushNamed('agent-environment'),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Environment',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.count,
    required this.countLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String blurb;

  /// `null` while the backing list is still loading — the row shows nothing
  /// rather than a misleading "0 sessions".
  final int? count;
  final String countLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 21, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        if (count != null && count! > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blurb,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        count == 0
                            ? 'No ${countLabel}s yet'
                            : '$count $countLabel${count == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
