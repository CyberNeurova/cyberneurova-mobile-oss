import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/core/agent/device/pane_label.dart';

import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// The session sidebar — every open shell, and the panes inside the current one.
///
/// This is the multiplexer made visible. `ShellWorkspaceRegistry` already holds
/// sessions above the widget tree so they outlive the screen; until now there
/// was no way to see or reach them from inside a session, so "multiple shells"
/// existed in the model and not in the product.
///
/// Layout mirrors how tmux is actually used: sessions are the outer list,
/// panes belong to the focused session and are shown nested under it. A pane
/// list for every session at once would be noise — you only ever switch panes
/// within the shell you're looking at.
class ShellSessionsDrawer extends StatelessWidget {
  const ShellSessionsDrawer({
    super.key,
    required this.registry,
    required this.activeId,
    required this.onSelectSession,
    required this.onSelectPane,
    required this.onNewPane,
    required this.onClosePane,
    required this.onNewSession,
    required this.onDeleteSession,
  });

  final ShellWorkspaceRegistry registry;
  final String activeId;
  final ValueChanged<ShellWorkspace> onSelectSession;
  final ValueChanged<int> onSelectPane;
  final VoidCallback onNewPane;
  final ValueChanged<String> onClosePane;
  final VoidCallback onNewSession;

  /// (session, keepFiles) — the two are asked separately because closing a
  /// conversation and destroying what it built are different intentions.
  final void Function(ShellWorkspace, bool keepFiles) onDeleteSession;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sessions = registry.all;

    // Same 32dp curve as the main app drawer (`app_drawer.dart`). Two drawers
    // in one app with different silhouettes reads as two different apps.
    const radius = BorderRadius.only(
      topRight: Radius.circular(32),
      bottomRight: Radius.circular(32),
    );

    return Drawer(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      // Inset by the system bars, same as the main drawer: a full-bleed drawer
      // puts its corners under the status and navigation bars, where rounding
      // cannot be seen. Measured on device — see app_drawer.dart.
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.viewPaddingOf(context).top,
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
        color: cs.surface,
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Text(
                'CyberNeurova',
                style: AppTheme.serifDisplay(
                  size: 19,
                  weight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 9),
                  Text(
                    'Shells',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${sessions.length}',
                    style: AppTheme.mono(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.35)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final ws in sessions) ...[
                    _SessionTile(
                      workspace: ws,
                      isActive: ws.id == activeId,
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelectSession(ws);
                      },
                      onDelete: () => _confirmDelete(context, ws),
                    ),
                    // What this session has built. Shown under the session it
                    // belongs to, because a project only means anything in
                    // the context of the conversation that produced it.
                    if (ws.id == activeId)
                      for (final proj in ws.projects())
                        _ProjectTile(project: proj),
                    // Panes only for the session in view — see class doc.
                    if (ws.id == activeId)
                      for (var i = 0; i < ws.paneCount; i++)
                        _PaneTile(
                          pane: ws.panes[i],
                          isActive: i == ws.activeIndex,
                          canClose: ws.paneCount > 1,
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelectPane(i);
                          },
                          onClose: () => onClosePane(ws.panes[i].id),
                        ),
                    if (ws.id == activeId)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(46, 2, 12, 8),
                        child: _InlineAction(
                          icon: Icons.add_rounded,
                          label: 'New pane',
                          onTap: () {
                            Navigator.of(context).pop();
                            onNewPane();
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.35)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onNewSession();
                  },
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New shell'),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
      ),
      ),
    );
  }

  /// Asks what to do with the work before removing a session.
  ///
  /// Three answers, not two. "Delete" alone would force a choice between
  /// keeping a conversation you are done with and keeping the only copy of
  /// what it built — and on a phone it IS the only copy, with no second
  /// machine it was synced to.
  Future<void> _confirmDelete(BuildContext context, ShellWorkspace ws) async {
    final projects = ws.projects();
    final cs = Theme.of(context).colorScheme;

    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${ws.displayName}?'),
        content: Text(
          projects.isEmpty
              ? 'This session has no saved work.'
              : 'This session has ${projects.length} '
                  '${projects.length == 1 ? 'project' : 'projects'}: '
                  '${projects.map((p) => p.name).join(', ')}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          if (projects.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Keep the files'),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cs.error),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(projects.isEmpty ? 'Delete' : 'Delete everything'),
          ),
        ],
      ),
    );

    if (keep == null || !context.mounted) return;
    Navigator.of(context).pop();
    onDeleteSession(ws, keep);
  }
}

/// One thing a session built.
class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});

  final SessionProject project;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(46, 2, 12, 2),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(fontSize: 12, color: cs.onSurface),
            ),
          ),
          Text(
            project.summary,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.workspace,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  final ShellWorkspace workspace;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = workspace.panes.where((p) => p.isRunning).length;

    return Semantics(
      button: true,
      selected: isActive,
      label: 'Shell ${workspace.displayName}, '
          '${workspace.paneCount} panes, $running running',
      child: Material(
        color: isActive ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Active marker is a bar, not just colour — colour alone must
                // never be the only carrier of state (WCAG).
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isActive ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspace.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          fontSize: 13.5,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? cs.primary : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${workspace.paneCount} pane'
                        '${workspace.paneCount == 1 ? '' : 's'}'
                        '${running > 0 ? ' · $running running' : ''}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Visible, not a long-press. A destructive action that can
                // only be found by holding a row is one people discover by
                // accident, and this one can take a project with it.
                IconButton(
                  tooltip: 'Delete session',
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  iconSize: 17,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: cs.onSurfaceVariant),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneTile extends StatelessWidget {
  const _PaneTile({
    required this.pane,
    required this.isActive,
    required this.canClose,
    required this.onTap,
    required this.onClose,
  });

  final ShellPane pane;
  final bool isActive;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: isActive,
      label: 'Pane ${pane.label.value}, ${pane.status.description}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(46, 6, 8, 6),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Hollow for never-started, error colour for died: the
                    // three cases a bool collapsed into "not running".
                    color: switch (pane.status) {
                      PaneStatus.running => cs.primary,
                      PaneStatus.failed => cs.error,
                      PaneStatus.exited =>
                        cs.onSurfaceVariant.withValues(alpha: 0.45),
                      PaneStatus.idle => Colors.transparent,
                    },
                    border: pane.status == PaneStatus.idle
                        ? Border.all(color: cs.outline, width: 1)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: pane.label,
                    builder: (context, label, _) => Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        fontSize: 12.5,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w400,
                        color: isActive ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (canClose)
                  IconButton(
                    tooltip: 'Close pane',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({
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
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
