import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';

final imageRepositoryProvider = Provider<ImageRepository>((ref) {
  return ImageRepository(ref.watch(apiClientProvider));
});

class ImageRepository {
  ImageRepository(this._client);
  final ApiClient _client;

  Future<ImageListResponse> listImages({String? cursor}) async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.IMAGES,
      queryParameters: {
        'limit': AppConstants.defaultPageLimit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return ImageListResponse.fromJson(res.data!);
  }

  /// Generate an image. As of 2026-06-05 the API is **synchronous** —
  /// the server runs Ideogram 4 fp8 on Box A and returns the persisted
  /// image URL when generation completes (~15s for 1024×1024). No
  /// polling needed.
  ///
  /// Throws an [AppException] (set by ErrorInterceptor) on tier/budget/
  /// upstream errors; the calling provider translates those to UI
  /// state.
  Future<ImageGenerateResponse> generateImage({
    required String prompt,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.IMAGES_GENERATE,
      data: {'prompt': prompt},
    );
    return ImageGenerateResponse.fromJson(res.data!);
  }

  /// Delete a generated image.
  ///
  /// Chat-team's inbox/019 shipped a mobile-namespaced route at
  /// `DELETE /api/mobile/v1/images/<uuid>` (audit logged under
  /// `mobile_image_deleted`). Build 12 hit the web-origin route at
  /// `/api/images/<uuid>` with an absolute URL hack — now using the
  /// proper namespaced path under the ApiClient's baseUrl.
  Future<void> deleteImage(String imageId) async {
    if (imageId.isEmpty) {
      throw ArgumentError('imageId is empty');
    }
    await _client.delete<dynamic>('${ApiConstants.IMAGES}/$imageId');
  }
}
