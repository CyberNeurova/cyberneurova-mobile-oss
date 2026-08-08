import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';

final imageDownloaderProvider =
    Provider<ImageDownloader>((ref) => ImageDownloader(ref));

/// Thrown by [ImageDownloader] when the user denies (or has previously
/// denied) the Photos add permission. Distinct type so UI can branch
/// to a "Open Settings → CyberNeurova" hint instead of a generic error.
class PhotosPermissionDeniedException implements Exception {
  const PhotosPermissionDeniedException();
  @override
  String toString() => 'PhotosPermissionDeniedException';
}

/// Download a generated/uploaded image to the device's photo library.
///
/// The image URL is auth-protected on the server side (same reason
/// `AuthedNetworkImage` exists), so we issue a one-off Dio request with
/// the Bearer header instead of going through `flutter_cache_manager`.
/// `gal` handles the platform-specific Photos / MediaStore add APIs.
///
/// Throws on:
///   - No access token (user not signed in — shouldn't happen on this UI)
///   - HTTP failure
///   - `GalException(accessDenied)` — caller should show an "Open
///     Settings" toast so the user can flip the permission
class ImageDownloader {
  ImageDownloader(this._ref);
  final Ref _ref;

  Future<void> saveToGallery({
    required String imageUrl,
    String? album,
    String? fileName,
  }) async {
    final token = _ref.read(currentAccessTokenProvider);
    // Sahachiel: attach the Bearer ONLY to our own secure origin — never leak
    // the access token to a third-party or cleartext image host.
    final sameOrigin = ApiConstants.isOwnOrigin(imageUrl);
    if (sameOrigin && token == null) {
      throw StateError('Not signed in — no access token to fetch image.');
    }

    // Standalone Dio — bypass the ApiClient's JSON content-type
    // baseOptions + the 401-refresh interceptor (which is fine for API
    // routes but unnecessary for a one-off binary fetch).
    final dio = Dio();
    final res = await dio.get<List<int>>(
      imageUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: sameOrigin ? {'Authorization': 'Bearer $token'} : null,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('HTTP ${res.statusCode}: image download failed');
    }

    // gal triggers the OS permission prompt on the first call.
    final hasAccess = await Gal.hasAccess(toAlbum: album != null);
    if (!hasAccess) {
      final granted = await Gal.requestAccess(toAlbum: album != null);
      if (!granted) {
        // GalException's constructor needs internal PlatformException
        // fields we don't have here, so wrap as a typed sentinel the
        // caller can pattern-match on for the "open settings" toast.
        throw const PhotosPermissionDeniedException();
      }
    }

    await Gal.putImageBytes(
      Uint8List.fromList(res.data!),
      album: album,
      // `gal` requires a name once you pass one at all; fall back to the
      // album so a caller that has no prompt still gets something better
      // than the package default of "image".
      name: fileName ?? 'cyberneurova',
    );
  }
}

/// A filename a person can find their picture by.
///
/// `gal` names the file `image` when it is not told otherwise, so every save
/// landed as `Pictures/CyberNeurova/image.png` — verified on device
/// 2026-08-05. Saving a second picture gives you two files called the same
/// thing and no way to tell which prompt made which.
///
/// The prompt is the only thing the user actually remembers about an image, so
/// it leads. The id follows to keep two different pictures apart, and to make
/// saving the SAME picture twice idempotent rather than a duplicate.
String galleryFileName({required String prompt, required String id}) {
  final slug = prompt
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+'), '')
      .replaceAll(RegExp(r'-+$'), '');
  final head = slug.isEmpty
      ? 'cyberneurova'
      : (slug.length > 48 ? slug.substring(0, 48).replaceAll(RegExp(r'-+$'), '') : slug);
  final tail = id.length > 8 ? id.substring(id.length - 8) : id;
  return tail.isEmpty ? head : '$head-$tail';
}
