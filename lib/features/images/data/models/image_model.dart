// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';

part 'image_model.freezed.dart';
part 'image_model.g.dart';

/// One row in the generated-images gallery.
///
/// Field-name mapping uses @JsonKey to match the chat-app API exactly
/// (`imageId`, `imageUrl`, `thumbnailUrl`, `aspectRatio`, ...) while
/// keeping the Dart-side names short (`id`, `url`).
///
/// `url` and `thumbnailUrl` go through [ApiConstants.resolveImageUrl] so
/// the API can return host-relative `/api/images/<id>/view` and the UI
/// still gets an absolute URL [CachedNetworkImage] can fetch.
@freezed
class ImageModel with _$ImageModel {
  const factory ImageModel({
    @JsonKey(name: 'imageId') required String id,
    @JsonKey(name: 'imageUrl', fromJson: ApiConstants.resolveImageUrl)
    required String url,
    @JsonKey(name: 'thumbnailUrl', fromJson: _resolveOptional)
    String? thumbnailUrl,
    required String prompt,
    @Default('artemis-img') String model,
    String? style,
    @JsonKey(name: 'aspectRatio') @Default('1:1') String aspectRatio,
    DateTime? createdAt,
    @Default(false) bool isPublished,
  }) = _ImageModel;

  factory ImageModel.fromJson(Map<String, dynamic> json) =>
      _$ImageModelFromJson(json);
}

String? _resolveOptional(String? v) =>
    v == null ? null : ApiConstants.resolveImageUrl(v);

/// Paginated list response — matches GET /api/mobile/v1/images.
@freezed
class ImageListResponse with _$ImageListResponse {
  const factory ImageListResponse({
    @Default([]) List<ImageModel> images,
    String? nextCursor,
    @Default(false) bool hasMore,
  }) = _ImageListResponse;

  // Constructs directly: coalesce the list key, skip malformed rows, and never
  // throw on a missing/null `images` (which would blank the whole gallery).
  factory ImageListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['images'] ?? json['data'] ?? json['items'];
    final images = <ImageModel>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          try {
            images.add(ImageModel.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // Skip a malformed row rather than failing the whole list.
          }
        }
      }
    }
    return ImageListResponse(
      images: images,
      nextCursor: json['nextCursor'] is String ? json['nextCursor'] as String : null,
      hasMore: json['hasMore'] is bool ? json['hasMore'] as bool : false,
    );
  }
}

/// Single-image response — what POST /api/mobile/v1/images/generate
/// returns after the (synchronous) Ideogram call finishes. The server
/// shape is:
///
///   {
///     "success": true,
///     "images": [{ "url": "/api/images/<uuid>/view" }],
///     "text": "...",
///     "usage": { used, limit, remaining, resetAt }
///   }
///
/// We promote the first image to a full [ImageModel] using
/// fromGenerateResponse so the rest of the codebase doesn't have to
/// know about the [{url}] subshape.
@freezed
class ImageGenerateResponse with _$ImageGenerateResponse {
  const factory ImageGenerateResponse({
    required bool success,
    required String url,
    String? text,
    ImageUsage? usage,
  }) = _ImageGenerateResponse;

  factory ImageGenerateResponse.fromJson(Map<String, dynamic> json) {
    // Sahachiel: parse every field defensively. The server response can drift or
    // be hostile - the first list element can be missing, null, or a non-map, and
    // `images.first as Map` / `url as String` used to throw a CastError and crash
    // the whole image-generate flow. Guard each access and fall back instead.
    final imgs = json['images'];
    final first = (imgs is List && imgs.isNotEmpty && imgs.first is Map)
        ? Map<String, dynamic>.from(imgs.first as Map)
        : <String, dynamic>{};
    final rawUrl = first['url'];
    final usage = json['usage'];
    return ImageGenerateResponse(
      success: json['success'] is bool ? json['success'] as bool : true,
      url: ApiConstants.resolveImageUrl(rawUrl is String ? rawUrl : ''),
      text: json['text'] is String ? json['text'] as String : null,
      usage: usage is Map
          ? ImageUsage.fromJson(Map<String, dynamic>.from(usage))
          : null,
    );
  }
}

@freezed
class ImageUsage with _$ImageUsage {
  const factory ImageUsage({
    required int used,
    required int limit,
    required int remaining,
    DateTime? resetAt,
  }) = _ImageUsage;

  factory ImageUsage.fromJson(Map<String, dynamic> json) =>
      _$ImageUsageFromJson(json);
}
