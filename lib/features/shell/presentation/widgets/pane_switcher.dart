import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/core/agent/device/pane_label.dart';
import 'package:flutter/services.dart';

import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// tmux-style pane strip.
///
/// A flat horizontal list, not a layout tree, because on a phone exactly one
/// pane is visible at a time — the real operations are select / next / new /
/// close (`shell_workspace.dart`). A split-view layout is a tablet concern.
///
/// Each chip shows a **running dot** so a pane doing work is visible without
/// switching to it, which is most of the value of a multiplexer.
class PaneSwitcher extends StatelessWidget {
  const PaneSwitcher({
    super.key,
    required this.workspace,
    required this.onSelect,
    required this.onNew,
    required this.onClose,
  });

  final ShellWorkspace workspace;
  final ValueChanged<int> onSelect;
  final VoidCallback onNew;
  final ValueChanged<String> onClose;

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final panes = workspace.panes;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outline.withValues(alpha: isLight ? 1.0 : 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: panes.length,
              itemBuilder: (context, i) {
                final pane = panes[i];
                // The label changes while the strip is on screen — a pane
                // becomes `nano` the moment nano opens — so it is watched
                // rather than read once at build.
                return ValueListenableBuilder<String>(
                  valueListenable: pane.label,
                  builder: (context, label, _) => _PaneChip(
                  index: i + 1,
                  label: label,
                  active: i == workspace.activeIndex,
                  status: pane.status,
                  // Only offer close when there's more than one — closing the
                  // last pane just makes a new one, so the button would be a
                  // lie.
                  onClose: panes.length > 1 ? () => onClose(pane.id) : null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(i);
                  },
                  ),
                );
              },
            ),
          ),
          Semantics(
            button: true,
            label: 'New pane',
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'New pane',
              icon: Icon(Icons.add_rounded, size: 20, color: cs.onSurface),
              onPressed: () {
                HapticFeedback.selectionClick();
                onNew();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneChip extends StatelessWidget {
  const _PaneChip({
    required this.index,
    required this.label,
    required this.active,
    required this.status,
    required this.onTap,
    this.onClose,
  });

  /// Kept alongside the name because the name is no longer unique: two panes
  /// sitting at a prompt are both `bash`, and tmux shows `1:bash` for exactly
  /// this reason.
  final int index;
  final String label;
  final bool active;
  final PaneStatus status;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: active,
        label: 'Pane $index, $label, ${status.description}',
        child: Material(
          color: active ? cs.primary.withValues(alpha: 0.14) : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.only(left: 10, right: onClose != null ? 4 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: active ? cs.primary : cs.outline,
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status indicator. Shape AND colour, never colour alone:
                  // running is filled, a pane that never started is hollow,
                  // and one that died is filled in the error colour. A bool
                  // could only ever draw two of those three.
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (status) {
                        PaneStatus.running => cs.primary,
                        PaneStatus.failed => cs.error,
                        PaneStatus.exited => cs.onSurfaceVariant,
                        PaneStatus.idle => Colors.transparent,
                      },
                      border: status == PaneStatus.idle
                          ? Border.all(color: cs.outline, width: 1)
                          : null,
                    ),
                  ),
                  Text(
                    '$index ',
                    style: AppTheme.mono(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  ConstrainedBox(
                    // Foreground-process labels must not push the strip wide.
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onClose != null)
                    Semantics(
                      button: true,
                      label: 'Close $label',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        icon: Icon(Icons.close_rounded,
                            color: cs.onSurfaceVariant),
                        onPressed: onClose,
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
}
