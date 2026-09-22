import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';

final uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  return UploadRepository(ref.watch(apiClientProvider));
});

class UploadResult {
  const UploadResult({
    required this.url,
    required this.pathname,
    required this.contentType,
    required this.name,
    required this.size,
  });

  final String url;
  final String pathname;
  final String contentType;
  final String name;
  final int size;

  factory UploadResult.fromJson(Map<String, dynamic> json) => UploadResult(
        // Sahachiel: read each field with an `is String` guard. The required
        // `url` was a bare `as String` (crashes on missing/null), and the
        // `(x ?? default) as String` form still cast a present non-string (e.g.
        // a number) and threw. Now every field degrades to its default instead.
        url: json['url'] is String ? json['url'] as String : '',
        pathname: json['pathname'] is String ? json['pathname'] as String : '',
        contentType: json['contentType'] is String
            ? json['contentType'] as String
            : 'application/octet-stream',
        name: json['name'] is String ? json['name'] as String : '',
        size: json['size'] is num ? (json['size'] as num).toInt() : 0,
      );
}

/// Uploads via the mobile-Bearer'd `/api/mobile/v1/files/upload` route
/// (chat-team round 7, inbox/007). Mirrors web policy 1:1: free tier is
/// capped at 2 MB per file, paid at 10 MB (6 MB for zip), 500 MB/24h
/// total. Server enforces both size + file-type allowlists.
class UploadRepository {
  UploadRepository(this._client);
  final ApiClient _client;

  /// Upload a local file as a chat attachment.
  ///
  /// [chatId] is REQUIRED — chat-team's engine-backed upload route
  /// (post-Vercel migration, inbox/015) uses it to scope the workspace
  /// path. Without it the engine returns 400 `INVALID_INPUT` and the
  /// file would also silently land in `<userId>/general/` instead of
  /// `<userId>/<chatId>/` causing later file-loss.
  Future<UploadResult> uploadFile({
    required String filePath,
    String? chatId,
    String? roomId,
    String? projectId,
    String? filename,
    String? contentType,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        // Override the on-disk name when given, so the filename extension
        // matches [contentType] + the actual bytes — the server rejects a
        // mismatch (an OS picker can hand back a JPEG named ".png").
        filename: filename,
        contentType:
            contentType != null ? DioMediaType.parse(contentType) : null,
      ),
      // A real chat scopes by a UUID [chatId]; a bot-section room has no chat,
      // so it scopes by [roomId]/[projectId] (the engine maps those to the
      // per-user "general" namespace, chat/core 2026-08-29). Send whichever the
      // caller provided — the route requires exactly one.
      if (chatId != null) 'chatId': chatId,
      if (roomId != null) 'roomId': roomId,
      if (projectId != null) 'projectId': projectId,
    });

    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.FILES_UPLOAD,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    return UploadResult.fromJson(res.data!);
  }
}
