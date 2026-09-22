import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/features/chat/data/repositories/upload_repository.dart';

/// One staged attachment in the collaboration composer — uploading or uploaded.
class BotAttachment {
  const BotAttachment({
    required this.id,
    required this.localPath,
    required this.contentType,
    this.url,
    this.name,
    this.uploading = false,
    this.error,
  });

  final String id;
  final String localPath;
  final String contentType;

  /// Durable engine-store URL (`/api/core/files/<id>`) once uploaded — the
  /// canonical image-block shape agreed with chat/core (no bot-section blob for
  /// persistent images).
  final String? url;
  final String? name;
  final bool uploading;
  final String? error;

  bool get isImage => contentType.startsWith('image/');
  bool get isUploaded => url != null;

  BotAttachment copyWith({
    String? url,
    String? name,
    bool? uploading,
    String? error,
    bool clearError = false,
  }) =>
      BotAttachment(
        id: id,
        localPath: localPath,
        contentType: contentType,
        url: url ?? this.url,
        name: name ?? this.name,
        uploading: uploading ?? this.uploading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Pending attachments for one collaboration room's composer, keyed by roomId.
/// Reuses the chat feature's durable uploader ([UploadRepository]) so a project
/// image lands in the same engine store the whole estate reads.
final botAttachmentsProvider = NotifierProviderFamily<BotAttachmentsNotifier,
    List<BotAttachment>, String>(BotAttachmentsNotifier.new);

class BotAttachmentsNotifier extends FamilyNotifier<List<BotAttachment>, String> {
  @override
  List<BotAttachment> build(String roomId) => const [];

  static const int maxAttachments = 5;

  Future<void> add({
    required String localPath,
    required String contentType,
  }) async {
    if (state.length >= maxAttachments) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    state = [
      ...state,
      BotAttachment(
        id: id,
        localPath: localPath,
        contentType: contentType,
        uploading: true,
      ),
    ];
    try {
      // Sniff the REAL type from the file's magic bytes — an OS picker can hand
      // back a JPEG named ".png", and the server rejects extension/content
      // mismatches. Send a filename whose extension matches so filename +
      // content-type + bytes all agree. Bot rooms scope by a `roomId` FIELD
      // (mapped to the per-user "general" namespace, chat/core 2026-08-29).
      final ct = await _sniffContentType(localPath, contentType);
      final res = await ref.read(uploadRepositoryProvider).uploadFile(
            filePath: localPath,
            roomId: arg,
            contentType: ct,
            filename: ct.startsWith('image/') ? 'upload${_extForMime(ct)}' : null,
          );
      state = [
        for (final a in state)
          if (a.id == id)
            a.copyWith(url: res.url, name: res.name, uploading: false)
          else
            a,
      ];
    } catch (e) {
      state = [
        for (final a in state)
          if (a.id == id) a.copyWith(error: e.toString(), uploading: false) else a,
      ];
    }
  }

  /// The real image type from the file header. The OS picker can mislabel a
  /// JPEG as `.png`; the server sniffs content, so we must agree. Non-image
  /// files keep [hint] (file_picker's extension is reliable).
  Future<String> _sniffContentType(String path, String hint) async {
    try {
      final raf = await File(path).open();
      final h = await raf.read(12);
      await raf.close();
      bool b(int i, int v) => h.length > i && h[i] == v;
      if (b(0, 0xFF) && b(1, 0xD8) && b(2, 0xFF)) return 'image/jpeg';
      if (b(0, 0x89) && b(1, 0x50) && b(2, 0x4E) && b(3, 0x47)) {
        return 'image/png';
      }
      if (b(0, 0x47) && b(1, 0x49) && b(2, 0x46)) return 'image/gif';
      if (b(0, 0x52) && b(1, 0x49) && b(2, 0x46) &&
          b(8, 0x57) && b(9, 0x45) && b(10, 0x42)) {
        return 'image/webp';
      }
    } catch (_) {}
    return hint;
  }

  String _extForMime(String mime) => switch (mime) {
        'image/jpeg' => '.jpg',
        'image/png' => '.png',
        'image/gif' => '.gif',
        'image/webp' => '.webp',
        _ => '.jpg',
      };

  void remove(String id) =>
      state = state.where((a) => a.id != id).toList();

  void clear() => state = const [];

  /// The uploaded attachments as message blocks (canonical shapes agreed with
  /// chat/core): `image` → durable `url`; other files → `file_ref` → `url`.
  List<Map<String, dynamic>> toBlocks() => [
        for (final a in state)
          if (a.url != null)
            if (a.isImage)
              {
                'type': 'image',
                'url': a.url,
                'mime': a.contentType,
                if (a.name != null && a.name!.isNotEmpty) 'alt': a.name,
              }
            else
              {
                'type': 'file_ref',
                'url': a.url,
                'name': a.name ?? '',
                'mime': a.contentType,
              },
      ];

  bool get hasUploading => state.any((a) => a.uploading);
}
