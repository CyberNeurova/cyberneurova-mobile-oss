import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/widgets/scope_sheet.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_options_menu.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/attachments_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Attach a photo or a file to an Ask turn.
///
/// ## Why the agent surfaces needed this most
///
/// Plain chat has had attachments for a long time; the agent surfaces never
/// did — which is backwards. The agent is the one that can act on a file: a
/// screenshot of an error, a log someone was sent, a config to fix. Without
/// this the only way to get a file in front of it on a phone was to describe
/// it in prose, which is exactly the "my phone is my only computer" case the
/// product exists for.
///
/// Shares [pendingAttachmentsProvider] with the chat composer rather than
/// keeping its own list, so an attachment picked here is the same object the
/// send path already knows how to upload and clear.
class AskAttachButton extends ConsumerWidget {
  const AskAttachButton({super.key, required this.chatId});

  final String chatId;

  /// The server's own cap. Enforced here so the refusal is immediate rather
  /// than after an upload the user waited for.
  static const int maxAttachments = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final pending = ref.watch(pendingAttachmentsProvider(chatId));

    return IconButton(
      tooltip: 'Attach',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(
        Icons.add_rounded,
        size: 20,
        color: pending.isEmpty ? cs.onSurfaceVariant : cs.primary,
      ),
      onPressed: () => _open(context, ref, pending.length),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, int already) async {
    HapticFeedback.selectionClick();
    final remaining = maxAttachments - already;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Up to 5 attachments per message'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final choice = await showModalBottomSheet<_AttachKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in _AttachKind.values)
              ListTile(
                leading: Icon(k.icon),
                title: Text(k.label),
                onTap: () => Navigator.of(ctx).pop(k),
              ),
            // The same two entries the chat composer's `+` offers. Ask had its
            // own attach sheet with only the three pickers, so the agent
            // surface — the one place tool access actually means something —
            // was the one place you could not reach it.
            const Divider(height: 12),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Add to project'),
              subtitle: const Text('Keep this conversation with related work'),
              onTap: () {
                Navigator.of(ctx).pop();
                showProjectPicker(context, ref, chatId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Tool access'),
              subtitle:
                  const Text('What the agent may reach on your network'),
              onTap: () {
                Navigator.of(ctx).pop();
                showScopeSheet(context, chatId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final notifier = ref.read(pendingAttachmentsProvider(chatId).notifier);
    switch (choice) {
      case _AttachKind.camera:
        await _addImages(notifier, await _shoot());
      case _AttachKind.photos:
        await _addImages(notifier, await _pickImages(remaining));
      case _AttachKind.files:
        await _addFiles(notifier, remaining);
    }
  }

  Future<List<XFile>> _shoot() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048);
    return picked == null ? const [] : [picked];
  }

  Future<List<XFile>> _pickImages(int limit) => ImagePicker()
      .pickMultiImage(imageQuality: 85, maxWidth: 2048, limit: limit);

  Future<void> _addImages(
      PendingAttachmentsNotifier notifier, List<XFile> picked) async {
    for (final p in picked) {
      // Sequential, matching the chat composer: a predictable chip order, and
      // no overlapping multipart streams competing for the connection pool.
      await notifier.add(
        localPath: p.path,
        contentType: p.mimeType ??
            (p.path.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg'),
      );
    }
  }

  Future<void> _addFiles(
      PendingAttachmentsNotifier notifier, int limit) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    for (final f in result.files.take(limit)) {
      final path = f.path;
      if (path == null) continue;
      await notifier.add(
        localPath: path,
        contentType: _contentTypeFor(f.extension),
      );
    }
  }

  static String _contentTypeFor(String? extension) => switch (extension) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'pdf' => 'application/pdf',
        'json' => 'application/json',
        'md' || 'txt' || 'csv' || 'log' => 'text/plain',
        _ => 'application/octet-stream',
      };
}

enum _AttachKind {
  camera('Take a photo', Icons.photo_camera_outlined),
  photos('Photos', Icons.image_outlined),
  files('Files', Icons.attach_file_rounded);

  const _AttachKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// What is queued, above the field.
///
/// Without this an attachment is invisible until it comes back in the
/// transcript — you cannot tell whether the picker worked, whether it is still
/// uploading, or remove one you picked by mistake.
class AskAttachmentStrip extends ConsumerWidget {
  const AskAttachmentStrip({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final pending = ref.watch(pendingAttachmentsProvider(chatId));
    if (pending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in pending)
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.uploading)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.check_rounded, size: 13, color: cs.primary),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      a.upload?.name ?? _basename(a.localPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTheme.mono(fontSize: 11, color: cs.onSurface),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: () => ref
                        .read(pendingAttachmentsProvider(chatId).notifier)
                        .remove(a.id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf(r'\');
    final cut = slash > back ? slash : back;
    return cut < 0 ? path : path.substring(cut + 1);
  }
}
