import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/projects/data/models/project_model.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/providers/projects_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Projects'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editProject(context, ref, null),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New project'),
        backgroundColor: cs.primary,
        // Navy on teal — white was low-contrast on the brand accent.
        foregroundColor: cs.onPrimary,
      ),
      body: projects.when(
        loading: () => const _ProjectsShimmer(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.refresh(projectsProvider.future),
        ),
        data: (list) => list.isEmpty
            ? _EmptyProjects(
                onCreate: () => _editProject(context, ref, null))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  MaxWidthContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // No l10n key exists for a section label — matches
                        // the hardcoded-string convention used in settings.
                        const _SectionHeader(label: 'All projects'),
                        _GroupCard(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0) const _Sep(),
                              _ProjectRow(
                                project: list[i],
                                onOpen: () => context.pushNamed(
                                  'project-detail',
                                  pathParameters: {'id': list[i].id},
                                ),
                                onEdit: () =>
                                    _editProject(context, ref, list[i]),
                                onDelete: () =>
                                    _confirmDelete(context, ref, list[i]),
                              ),
                            ],
                          ],
                        ).animate().fadeIn(duration: 250.ms),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _editProject(
    BuildContext context,
    WidgetRef ref,
    ProjectModel? existing,
  ) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ProjectEditor(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ProjectModel project,
  ) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'Chats inside "${project.name}" stay, but the grouping is lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Delete',
              style:
                  TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(projectsProvider.notifier).delete(project.id);
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

// ─── Project row ─────────────────────────────────────────────────────────────

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });
  final ProjectModel project;

  /// Tap → the project's chats. Previously tap opened the edit sheet, which
  /// contradicted the row's chevron and chat count and left no way at all to
  /// see what was actually inside a project.
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color _color(BuildContext context) {
    if (project.color != null && project.color!.startsWith('#')) {
      try {
        return Color(int.parse(
            'FF${project.color!.substring(1)}',
            radix: 16));
      } catch (_) {}
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// Rename / delete, reachable from the row's ⋯ button or a long-press.
  Future<void> _showActions(BuildContext context) async {
    HapticFeedback.selectionClick();
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit project'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: cs.error),
              title: Text('Delete project',
                  style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.pop(sheetCtx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _color(context);
    return InkWell(
      onTap: onOpen,
      // Long-press still offers the config actions, now as a menu rather than
      // jumping straight to a destructive delete confirm.
      onLongPress: () => _showActions(context),
      child: Padding(
        // 16/12 padding + 36px leading → ≥48px rows, on the 4/8 grid.
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                projectGlyph(project.icon),
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${project.chatCount} chat${project.chatCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Explicit affordance for the config actions — long-press alone
            // is undiscoverable, and tap is now spoken for by "open".
            IconButton(
              tooltip: 'Project options',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_horiz_rounded,
                  size: 20, color: cs.onSurfaceVariant),
              onPressed: () => _showActions(context),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

}

// ─── Loading skeleton (mirrors the grouped-card list) ────────────────────────

class _ProjectsShimmer extends StatelessWidget {
  const _ProjectsShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        MaxWidthContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: CnShimmer(width: 88, height: 12, radius: 6),
              ),
              _GroupCard(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i > 0) const _Sep(),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          CnShimmer(width: 36, height: 36, radius: 10),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CnShimmer(width: 160, height: 13, radius: 6),
                                SizedBox(height: 6),
                                CnShimmer(width: 72, height: 10, radius: 5),
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
          ),
        ),
      ],
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded,
                    size: 64, color: cs.primary.withValues(alpha: 0.3))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    begin: 1.0,
                    end: 1.08,
                    duration: 2000.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: 16),
            Text(
              'No projects',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Group related chats into projects to stay organized.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create first project'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Editor sheet ────────────────────────────────────────────────────────────

class _ProjectEditor extends ConsumerStatefulWidget {
  const _ProjectEditor({required this.existing});
  final ProjectModel? existing;

  @override
  ConsumerState<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends ConsumerState<_ProjectEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _icon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _description =
        TextEditingController(text: widget.existing?.description ?? '');
    _icon = TextEditingController(text: widget.existing?.icon ?? '📁');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _icon.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      if (widget.existing == null) {
        await ref.read(projectsProvider.notifier).create(
              name: name,
              description: description.isEmpty ? null : description,
              icon: _icon.text.trim().isEmpty ? null : _icon.text.trim(),
            );
      } else {
        await ref.read(projectsProvider.notifier).edit(
              widget.existing!.id,
              name: name,
              description: description.isEmpty ? null : description,
              icon: _icon.text.trim().isEmpty ? null : _icon.text.trim(),
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessageFor(context, e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              widget.existing == null ? 'New project' : 'Edit project',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _icon,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                    decoration:
                        const InputDecoration(labelText: 'Icon'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: cs.onPrimary))
                  : Text(widget.existing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The glyph to draw for a project.
///
/// `project.icon` is meant to be an emoji, but the server also stores NAMES —
/// this list rendered two projects as "fol", the word "folder" clipped to fit
/// a 36px box. Anything containing a Latin letter is a name, not a glyph: map
/// the handful we have seen and fall back to a folder for the rest. An emoji
/// passes through untouched.
String projectGlyph(String? icon) {
  final raw = (icon ?? '').trim();
  if (raw.isEmpty) return '📁';
  if (!RegExp(r'[A-Za-z]').hasMatch(raw)) return raw;
  return switch (raw.toLowerCase()) {
    'folder' || 'directory' => '📁',
    'code' || 'terminal' => '💻',
    'book' || 'notes' || 'docs' => '📓',
    'star' || 'favourite' || 'favorite' => '⭐',
    'rocket' || 'launch' => '🚀',
    'flask' || 'science' || 'research' => '🧪',
    _ => '📁',
  };
}
