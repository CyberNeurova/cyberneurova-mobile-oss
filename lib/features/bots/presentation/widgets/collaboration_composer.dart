import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cyberneurova_mobile/features/bots/presentation/providers/bot_attachments_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// The collaboration thread's input bar. Same visual language as the chat
/// composer (rounded pill, `+` attach sheet, attachment chips, round send) but
/// self-contained and wired to [botAttachmentsProvider] — no voice / model-
/// picker / device-hint coupling, so it can't regress the shipping chat.
class CollaborationComposer extends ConsumerStatefulWidget {
  const CollaborationComposer({
    super.key,
    required this.roomId,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final String roomId;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  ConsumerState<CollaborationComposer> createState() =>
      _CollaborationComposerState();
}

class _CollaborationComposerState extends ConsumerState<CollaborationComposer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  double get _outlineAlpha =>
      Theme.of(context).brightness == Brightness.light ? 1.0 : 0.35;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final paddingBottom = MediaQuery.of(context).padding.bottom;
    final attachments = ref.watch(botAttachmentsProvider(widget.roomId));
    final uploading = attachments.any((a) => a.uploading);
    final hasUploaded = attachments.any((a) => a.isUploaded);
    final canSend =
        (_hasText || hasUploaded) && !widget.sending && !uploading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, bottom > 0 ? bottom + 8 : paddingBottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty) ...[
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.only(start: 4),
                itemCount: attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _AttachmentChip(
                  attachment: attachments[i],
                  onRemove: () => ref
                      .read(botAttachmentsProvider(widget.roomId).notifier)
                      .remove(attachments[i].id),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border:
                  Border.all(color: cs.outline.withValues(alpha: _outlineAlpha)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widget.controller,
                  maxLines: 6,
                  minLines: 1,
                  style: TextStyle(fontSize: 16, height: 1.4, color: cs.onSurface),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle:
                        TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                    isDense: true,
                  ),
                ),
                Row(
                  children: [
                    _attachButton(cs),
                    const Spacer(),
                    _sendButton(cs, canSend),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachButton(ColorScheme cs) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openAttachSheet,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: cs.outline.withValues(alpha: _outlineAlpha)),
              ),
              child: Icon(Icons.add_rounded, size: 22, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendButton(ColorScheme cs, bool canSend) {
    return Material(
      color: canSend ? cs.primary : cs.surfaceContainerHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: canSend ? widget.onSend : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: widget.sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.arrow_upward_rounded,
                  size: 22,
                  color: canSend ? cs.onPrimary : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  void _openAttachSheet() {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    final remaining = BotAttachmentsNotifier.maxAttachments -
        ref.read(botAttachmentsProvider(widget.roomId)).length;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _sheetRow(cs, sheetCtx,
                  icon: Icons.camera_alt_outlined,
                  label: 'Take photo',
                  enabled: remaining > 0,
                  onTap: () => _pickImage(ImageSource.camera)),
              _sheetRow(cs, sheetCtx,
                  icon: Icons.photo_library_outlined,
                  label: 'Photo library',
                  enabled: remaining > 0,
                  onTap: () => _pickMultipleImages(remaining)),
              _sheetRow(cs, sheetCtx,
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Files',
                  enabled: remaining > 0,
                  onTap: () => _pickFiles(remaining)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetRow(
    ColorScheme cs,
    BuildContext sheetCtx, {
    required IconData icon,
    required String label,
    required bool enabled,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: enabled
          ? () {
              Navigator.of(sheetCtx).pop();
              onTap();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                ),
                child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, imageQuality: 85, maxWidth: 2048);
    if (picked == null) return;
    HapticFeedback.lightImpact();
    final ct = picked.mimeType ??
        (picked.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg');
    await ref
        .read(botAttachmentsProvider(widget.roomId).notifier)
        .add(localPath: picked.path, contentType: ct);
  }

  Future<void> _pickMultipleImages(int limit) async {
    final picked = await ImagePicker()
        .pickMultiImage(imageQuality: 85, maxWidth: 2048, limit: limit);
    if (picked.isEmpty) return;
    HapticFeedback.lightImpact();
    final notifier = ref.read(botAttachmentsProvider(widget.roomId).notifier);
    for (final p in picked) {
      final ct = p.mimeType ??
          (p.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      await notifier.add(localPath: p.path, contentType: ct);
    }
  }

  Future<void> _pickFiles(int limit) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'md', 'csv', 'json', 'zip',
        'py', 'js', 'ts', 'tsx', 'jsx', 'go', 'rs', 'java', 'c', 'cpp', 'h',
        'kt', 'swift', 'rb', 'sh',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    HapticFeedback.lightImpact();
    final notifier = ref.read(botAttachmentsProvider(widget.roomId).notifier);
    for (final f in result.files.take(limit)) {
      final path = f.path;
      if (path == null) continue;
      await notifier.add(
          localPath: path, contentType: _mimeFromExt(f.extension));
    }
  }

  String _mimeFromExt(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      case 'txt':
      case 'md':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final BotAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = Container(
      height: 64,
      width: attachment.isImage ? 64 : null,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: attachment.isImage && File(attachment.localPath).existsSync()
          ? Image.file(File(attachment.localPath), fit: BoxFit.cover)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      attachment.name ?? 'file',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (attachment.uploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.scrim.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          if (attachment.error != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.error_outline, color: cs.error, size: 20),
              ),
            ),
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onRemove();
              },
              // ~40px hit target (the visible circle stays 24px); the small
              // circle alone was below the min touch size and hard to tap.
              child: SizedBox(
                width: 40,
                height: 40,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surfaceContainerHighest,
                      border:
                          Border.all(color: cs.outline.withValues(alpha: 0.35)),
                    ),
                    child: Icon(Icons.close_rounded,
                        size: 14, color: cs.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
