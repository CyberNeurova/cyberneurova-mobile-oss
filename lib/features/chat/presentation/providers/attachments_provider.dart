import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/upload_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';

/// One staged attachment in the chat input — either uploading or uploaded.
class PendingAttachment {
  const PendingAttachment({
    required this.id,
    required this.localPath,
    required this.contentType,
    this.upload,
    this.error,
    this.uploading = false,
  });

  final String id;
  final String localPath;
  final String contentType;
  final UploadResult? upload;
  final String? error;
  final bool uploading;

  PendingAttachment copyWith({
    UploadResult? upload,
    String? error,
    bool? uploading,
  }) =>
      PendingAttachment(
        id: id,
        localPath: localPath,
        contentType: contentType,
        upload: upload ?? this.upload,
        error: error,
        uploading: uploading ?? this.uploading,
      );

  bool get isUploaded => upload != null;
}

/// Pending attachments for the current chat input. Keyed by chatId.
final pendingAttachmentsProvider = NotifierProviderFamily<
    PendingAttachmentsNotifier, List<PendingAttachment>, String>(
  PendingAttachmentsNotifier.new,
);

/// Set by the notifier when an upload fails for a reason that isn't a
/// paywall (network, 413 too-large, 5xx server). The chat detail screen
/// listens and surfaces a SnackBar so the failure doesn't sit silently
/// as a small red chip the user might miss.
final lastUploadErrorProvider = StateProvider<String?>((_) => null);

/// Maps an uploaded attachment's server URL to the local file path on
/// device. Populated at send-time by the composer so the optimistic user
/// bubble renders directly from disk instead of round-tripping the
/// server's `/api/core/files/<path>` proxy — which doesn't accept our
/// Bearer auth header (it was designed for `<img src=...>` with a web
/// session cookie). Session-scoped only — older messages reloaded from
/// history still go through the network path.
final localAttachmentPathsProvider =
    StateProvider<Map<String, String>>((_) => {});

class PendingAttachmentsNotifier
    extends FamilyNotifier<List<PendingAttachment>, String> {
  @override
  List<PendingAttachment> build(String chatId) => const [];

  Future<void> add({
    required String localPath,
    required String contentType,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final stub = PendingAttachment(
      id: id,
      localPath: localPath,
      contentType: contentType,
      uploading: true,
    );
    state = [...state, stub];

    try {
      final result = await ref.read(uploadRepositoryProvider).uploadFile(
            filePath: localPath,
            chatId: arg, // family arg = chatId
            contentType: contentType,
          );
      state = [
        for (final a in state)
          if (a.id == id) a.copyWith(upload: result, uploading: false) else a
      ];
    } catch (e) {
      // 403 TIER_REQUIRED → paywall. Other errors stay on the chip so
      // the user can retry. The chip strip in the composer subscribes to
      // [pendingPaywallTriggerProvider] and surfaces the upgrade sheet.
      if (e is ForbiddenException && e.code == 'TIER_REQUIRED') {
        // Remove the chip optimistically — user shouldn't have a dead
        // upload sitting in the composer after we tell them to upgrade.
        state = state.where((a) => a.id != id).toList();
        ref.read(pendingPaywallTriggerProvider.notifier).state =
            const PaywallTrigger(reason: PaywallReason.fileUpload);
      } else {
        final shortError = _shortError(e);
        state = [
          for (final a in state)
            if (a.id == id)
              a.copyWith(error: shortError, uploading: false)
            else
              a
        ];
        // Trigger a SnackBar — the small red chip overlay was easy to
        // miss, so users reported "upload doesn't work" thinking nothing
        // happened. The chip stays so they can tap into the dialog for
        // the full error + a retry/remove path; the SnackBar just makes
        // sure the failure is loud.
        ref.read(lastUploadErrorProvider.notifier).state = shortError;
      }
    }
  }

  /// A failed upload, in words the user can act on.
  ///
  /// This was `e.toString()` capped at 120 characters — the comment said the
  /// chip "can't render a wall of stack trace", which concedes that a stack
  /// trace was what it rendered. The cap made it shorter, not readable, and
  /// this string goes straight into a SnackBar.
  ///
  /// Same family as the "fetch failed" that Imagine showed. `AppException`
  /// carries a server message that is usually written for a person, so it is
  /// preferred — unless it is machine noise, which the server does sometimes
  /// send.
  static String _shortError(Object e) {
    if (e is AppException && !isTechnicalErrorMessage(e.message)) {
      final m = e.message.trim();
      return m.length > 120 ? '${m.substring(0, 117)}…' : m;
    }
    return "Couldn't upload that file. Try again.";
  }

  void remove(String id) {
    state = state.where((a) => a.id != id).toList();
  }

  void clear() {
    state = const [];
  }

  /// Returns the JSON shape the backend expects in /chat/:id/complete.
  List<Map<String, dynamic>> toApiAttachments() {
    return [
      for (final a in state)
        if (a.upload != null)
          {
            'url': a.upload!.url,
            'contentType': a.upload!.contentType,
            'name': a.upload!.name,
          }
    ];
  }
}
