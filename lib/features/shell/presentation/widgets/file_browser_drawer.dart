import 'dart:io';
import 'package:cyberneurova_mobile/shared/format/byte_size.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/file_browser.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/core/agent/device/apk_install.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cyberneurova_mobile/core/agent/device/session_import.dart';
import 'package:share_plus/share_plus.dart';

/// The project files, as a panel.
///
/// ## Why a terminal needs one
///
/// You can already `ls` — but on a phone `ls` costs a keyboard, a command, and
/// a screen of output you then scroll past to type the next one. Finding a file
/// three directories down is a dozen taps, and reading it means `cat` and a
/// wall of unwrapped text in a 40-column grid.
///
/// The panel is the same information at a glance, and it is the piece that
/// makes "the phone is my only computer" survive contact with an actual
/// project.
///
/// ## It shows the shell's filesystem, not a second one
///
/// Every path goes through [FileBrowser], which shares [ShellSession]'s
/// containment check with `cd`. So the panel cannot show somewhere the shell
/// would refuse to go, and "open here" lands the terminal exactly where the
/// user was looking. Two views of one filesystem — the same promise the Shell
/// and Ask tabs make about one session.
class FileBrowserDrawer extends StatefulWidget {
  const FileBrowserDrawer({
    super.key,
    required this.session,
    required this.onOpenFile,
    required this.onChangeDirectory,
    required this.onImported,
  });

  final ShellSession session;

  /// Show a file. The screen decides how — a viewer route, a sheet.
  final void Function(BrowseEntry entry) onOpenFile;

  /// Take the terminal to this directory. The panel does not run `cd` itself:
  /// the command belongs in the user's scrollback, where they can see it.
  final void Function(String guestPath) onChangeDirectory;

  /// Files that just arrived from the phone. The screen decides how to say so
  /// — a file appearing in a directory with no explanation reads as a bug.
  final void Function(List<ImportedFile> files) onImported;

  @override
  State<FileBrowserDrawer> createState() => _FileBrowserDrawerState();
}

class _FileBrowserDrawerState extends State<FileBrowserDrawer> {
  late FileBrowser _browser;
  late String _path;
  BrowseResult? _result;
  bool _importing = false;

  /// Multi-select. Entered by long-pressing a row; while on, a tap toggles
  /// instead of opening, and a batch bar replaces the header. Deleting ten
  /// scratch files one long-press-and-confirm at a time is the friction this
  /// removes. Keyed by guestPath — the stable id — and cleared on navigation,
  /// because a selection only means something within one directory.
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _browser = FileBrowser(widget.session);
    // Opens where the user is, not at the root. The cwd is the answer to
    // "what am I working on" nine times out of ten.
    _path = widget.session.cwd;
    _load();
  }

  void _load() {
    // Synchronous on purpose. These are local stats on a directory the user
    // just asked for; an async hop would cost a frame of empty list for work
    // that takes under a millisecond.
    setState(() => _result = _browser.list(_path));
  }

  void _go(String guestPath) {
    _path = guestPath;
    // A selection is per-directory; leaving clears it rather than acting on
    // paths that are no longer on screen.
    _selecting = false;
    _selected.clear();
    _load();
  }

  // ── multi-select ──────────────────────────────────────────────────────────

  List<BrowseEntry> get _selectedEntries {
    final r = _result;
    if (r == null) return const [];
    return [for (final e in r.entries) if (_selected.contains(e.guestPath)) e];
  }

  void _toggle(BrowseEntry entry) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(entry.guestPath)) _selected.remove(entry.guestPath);
      // Emptying the selection leaves selection mode — matches Files/Photos, so
      // there is no stranded empty toolbar.
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final items = _selectedEntries;
    if (items.isEmpty) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${items.length} item'
            '${items.length == 1 ? '' : 's'}?'),
        content: const Text('This includes anything inside a selected folder. '
            'There is no undo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    var failed = 0;
    for (final e in items) {
      try {
        if (e.isDirectory) {
          Directory(e.hostPath).deleteSync(recursive: true);
        } else {
          File(e.hostPath).deleteSync();
        }
      } on FileSystemException {
        failed++;
      }
    }
    _exitSelection();
    _load();
    if (failed > 0) {
      _say('$failed item${failed == 1 ? '' : 's'} could not be deleted.');
    }
  }

  Future<void> _shareSelected() async {
    // Android shares files, not directories — a folder in a share sheet only
    // ever fails, so drop them and say so if that leaves nothing.
    final files = [
      for (final e in _selectedEntries)
        if (!e.isDirectory) XFile(e.hostPath, name: e.name),
    ];
    if (files.isEmpty) {
      _say('Folders can\'t be shared. Select files to send.');
      return;
    }
    try {
      await Share.shareXFiles(files);
    } catch (e) {
      if (mounted) _say('Could not share: ${userMessageFor(context, e)}');
    }
  }

  Widget _selectionBar(ColorScheme cs) {
    final n = _selected.length;
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 21),
          onPressed: _exitSelection,
        ),
        Expanded(
          child: Text(
            '$n selected',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        // Rename is a single-item action — it only appears with exactly one
        // selected, and reuses the same flow the long-press sheet uses.
        if (n == 1)
          IconButton(
            tooltip: 'Rename',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
            onPressed: () async {
              final e = _selectedEntries.first;
              _exitSelection();
              await _rename(e);
            },
          ),
        IconButton(
          tooltip: 'Send a copy',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          onPressed: _shareSelected,
        ),
        IconButton(
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.delete_outline_rounded, size: 21, color: cs.error),
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final result = _result;
    final parent = _browser.parentOf(_path);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.86,
      backgroundColor: cs.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              child: _selecting
                  ? _selectionBar(cs)
                  : Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.folder_open_rounded,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Files',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Select',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.checklist_rounded, size: 20),
                            onPressed: (_result?.entries.isEmpty ?? true)
                                ? null
                                : () => setState(() => _selecting = true),
                          ),
                          IconButton(
                            tooltip: 'New folder',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.create_new_folder_outlined,
                                size: 19),
                            onPressed: _newFolder,
                          ),
                          IconButton(
                            tooltip: 'Bring a file in',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_rounded, size: 21),
                            onPressed: _importing ? null : _import,
                          ),
                          IconButton(
                            tooltip: 'Refresh',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.refresh_rounded, size: 19),
                            onPressed: _load,
                          ),
                        ],
                      ),
                    ),
            ),
            _Breadcrumb(
              display: _browser.display(_path),
              onRoot: () => _go(widget.session.rootDir),
            ),
            const Divider(height: 1),
            Expanded(
              child: result == null
                  ? const SizedBox.shrink()
                  : !result.ok
                      ? _Message(
                          icon: Icons.block_rounded,
                          text: result.error!,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          // +1 for the "up" row when there is somewhere to go.
                          itemCount:
                              result.entries.length + (parent == null ? 0 : 1),
                          itemBuilder: (context, i) {
                            if (parent != null && i == 0) {
                              return _UpRow(onTap: () => _go(parent));
                            }
                            final entry =
                                result.entries[parent == null ? i : i - 1];
                            return _EntryRow(
                              entry: entry,
                              selecting: _selecting,
                              selected: _selected.contains(entry.guestPath),
                              // Long-press opens the single-item sheet (rename/
                              // share/delete with a per-item confirmation);
                              // batch selection is entered from the Select
                              // button instead, so both flows coexist. In
                              // selection mode long-press just toggles.
                              onLongPress: () => _selecting
                                  ? _toggle(entry)
                                  : _manage(entry),
                              onTap: () {
                                // In selection mode a tap toggles rather than
                                // opening — you cannot both pick and navigate.
                                if (_selecting) {
                                  _toggle(entry);
                                  return;
                                }
                                if (entry.isDirectory) {
                                  _go(entry.guestPath);
                                } else if (p
                                    .extension(entry.name)
                                    .toLowerCase() == '.apk') {
                                  // An APK is not something to READ. The only
                                  // thing anyone wants from one is to install
                                  // it, and opening 40 MB of binary in a text
                                  // viewer is the wrong answer to the tap.
                                  _offerInstall(entry);
                                } else {
                                  Navigator.of(context).pop();
                                  widget.onOpenFile(entry);
                                }
                              },
                            );
                          },
                        ),
            ),
            if (result != null && result.ok) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _countLabel(result),
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop();
                        widget.onChangeDirectory(_path);
                      },
                      icon: const Icon(Icons.terminal_rounded, size: 17),
                      label: const Text('Open here'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Rename, delete, or make a folder — the operations a file list is for.
  ///
  /// The agent got the same three as tools. This is the user's half: without
  /// it the only way to rename something on a phone is to open a terminal and
  /// type `mv`, which is exactly the friction this panel exists to remove.
  Future<void> _manage(BrowseEntry entry) async {
    HapticFeedback.selectionClick();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(fontSize: 13.5),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            // Directories cannot go through a share sheet — Android shares
            // files, and offering it on a folder would only ever fail.
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Send a copy'),
                subtitle: const Text('To another app, or off this phone'),
                onTap: () => Navigator.pop(ctx, 'share'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'rename') await _rename(entry);
    if (action == 'delete') await _delete(entry);
    if (action == 'share') await _share(entry);
  }

  /// Hands the file to Android's share sheet.
  ///
  /// ## Why this is the piece that was missing
  ///
  /// Files could come IN — the picker imports them — and never leave. On a
  /// phone that is a one-way door: you build a thing and it stays trapped in
  /// an app-private directory no other app can read. "I made this, now send it
  /// to someone" is most of why anyone builds anything on a phone at all.
  ///
  /// A copy, never a move. The session keeps its file; the share sheet decides
  /// what happens to the duplicate. Anything else would mean tapping the wrong
  /// target silently removes your work.
  Future<void> _share(BrowseEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await Share.shareXFiles(
        [XFile(entry.hostPath, name: entry.name)],
        // The name travels with it. Without this the receiving app sees the
        // container path, which on this platform is a hash.
        fileNameOverrides: [entry.name],
      );
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Nothing on this phone can receive that file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not share ${entry.name}. '
              '${userMessageFor(context, e)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rename(BrowseEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty || trimmed == entry.name) return;

    // Same sanitising the import path uses: a slash here would write outside
    // the directory, and a leading dot would hide the file the user just
    // renamed, which reads as the rename having failed.
    final safe = SessionImport.safeName(trimmed);
    final target = p.join(p.dirname(entry.hostPath), safe);
    if (File(target).existsSync() || Directory(target).existsSync()) {
      _say('$safe already exists.');
      return;
    }
    try {
      if (entry.isDirectory) {
        Directory(entry.hostPath).renameSync(target);
      } else {
        File(entry.hostPath).renameSync(target);
      }
    } on FileSystemException catch (e) {
      _say('Could not rename: ${e.message}');
      return;
    }
    _load();
  }

  Future<void> _delete(BrowseEntry entry) async {
    // Counted BEFORE asking, so the confirmation can say how much is at stake.
    // "Delete work?" and "Delete work and the 34 things in it?" are different
    // questions and deserve different answers.
    var contained = 0;
    if (entry.isDirectory) {
      try {
        contained = Directory(entry.hostPath).listSync().length;
      } catch (_) {
        contained = 0;
      }
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text(
          contained > 0
              ? 'This also deletes the $contained item'
                  '${contained == 1 ? '' : 's'} inside it. There is no undo.'
              : 'There is no undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    try {
      if (entry.isDirectory) {
        Directory(entry.hostPath).deleteSync(recursive: true);
      } else {
        File(entry.hostPath).deleteSync();
      }
    } on FileSystemException catch (e) {
      _say('Could not delete: ${e.message}');
      return;
    }
    _load();
  }

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;

    final host = widget.session.resolveWithin(_path);
    if (host == null) return;
    try {
      Directory(p.join(host, SessionImport.safeName(trimmed)))
          .createSync(recursive: true);
    } on FileSystemException catch (e) {
      _say('Could not create the folder: ${e.message}');
      return;
    }
    _load();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Copies a file from the phone into this directory.
  ///
  /// The only way in. Android's picker can reach the user's photos and
  /// downloads; nothing else can put a byte inside this app's sandbox, so
  /// without this a session can only ever work with files it made itself.
  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (picked == null || picked.files.isEmpty) return;

      final paths = [
        for (final f in picked.files)
          if (f.path != null) f.path!,
      ];
      if (paths.isEmpty) return;

      final result = await SessionImport.copyInto(
        widget.session,
        paths,
        intoGuestDir: _path,
      );
      if (!mounted) return;

      if (!result.isOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error!),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      _load();
      widget.onImported(result.files);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Confirms, then hands the APK to Android.
  ///
  /// Our dialog is not the security boundary — Android draws its own
  /// confirmation after this one, and that is the one that matters. This exists
  /// so a mis-tap in a file list does not start an install flow the user did
  /// not mean to start.
  Future<void> _offerInstall(BrowseEntry entry) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install this app?'),
        content: Text(
          '${entry.name}\n\nAndroid will ask you to confirm as well.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    if (!await ApkInstall.isAllowed()) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow installing apps'),
          // Named for the screen they will actually see, because "permission
          // denied" is true and useless.
          content: const Text(
            'Android needs you to allow CyberNeurova to install apps. It is '
            'one switch, on the next screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (open == true) await ApkInstall.openPermissionSettings();
      return;
    }

    if (!mounted) return;
    // Captured BEFORE the await: the install waits on a system dialog, and by
    // the time it answers this drawer may well be gone.
    final messenger = ScaffoldMessenger.of(context);
    final result = await ApkInstall.install(entry.hostPath);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.outcome) {
          InstallOutcome.success => 'Installed ${entry.name}',
          InstallOutcome.declined => 'Install cancelled',
          InstallOutcome.notPermitted =>
            result.message ?? 'Not allowed to install apps',
          _ => result.message ?? 'Install failed',
        }),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _countLabel(BrowseResult r) {
    final dirs = r.entries.where((e) => e.isDirectory).length;
    final files = r.entries.length - dirs;
    if (r.entries.isEmpty) return 'Empty';
    return '$dirs folder${dirs == 1 ? '' : 's'} · '
        '$files file${files == 1 ? '' : 's'}';
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.display, required this.onRoot});

  final String display;
  final VoidCallback onRoot;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: GestureDetector(
        onTap: onRoot,
        child: Row(
          children: [
            Expanded(
              child: Text(
                shortenPath(display),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpRow extends StatelessWidget {
  const _UpRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(Icons.arrow_upward_rounded, size: 19, color: cs.primary),
      title: Text('..',
          style: AppTheme.mono(fontSize: 13.5, color: cs.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final BrowseEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dimmed = !entry.isDirectory && !entry.looksTextual;

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      selected: selected,
      selectedTileColor: cs.primary.withValues(alpha: 0.10),
      leading: selecting
          ? Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            )
          : Icon(
              entry.isDirectory ? Icons.folder_rounded : _iconFor(entry.name),
              size: 19,
              // Binaries stay visible but recede: they are part of the project
              // and hiding them would make the listing lie, but they are not
              // what the user is reaching for.
              color: entry.isDirectory
                  ? cs.primary
                  : (dimmed
                      ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                      : cs.onSurfaceVariant),
            ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.mono(
          fontSize: 13.5,
          color: dimmed
              ? cs.onSurfaceVariant
              : cs.onSurface,
        ),
      ),
      subtitle: entry.isDirectory || entry.size == null
          ? null
          : Text(
              humanBytes(entry.size!),
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
      trailing: entry.isLink
          ? Icon(Icons.link_rounded, size: 15, color: cs.onSurfaceVariant)
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  static IconData _iconFor(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.dart':
      case '.py':
      case '.js':
      case '.ts':
      case '.rs':
      case '.go':
      case '.c':
      case '.h':
      case '.cpp':
      case '.java':
      case '.kt':
      case '.rb':
      case '.php':
        return Icons.code_rounded;
      case '.md':
      case '.txt':
      case '.rst':
        return Icons.article_outlined;
      case '.json':
      case '.yaml':
      case '.yml':
      case '.toml':
      case '.xml':
      case '.ini':
      case '.conf':
        return Icons.data_object_rounded;
      case '.sh':
      case '.bash':
      case '.zsh':
        return Icons.terminal_rounded;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
        return Icons.image_outlined;
      case '.zip':
      case '.gz':
      case '.tar':
      case '.xz':
        return Icons.folder_zip_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
