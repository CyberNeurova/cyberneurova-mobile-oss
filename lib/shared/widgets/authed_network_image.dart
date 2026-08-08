import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';

/// [CachedNetworkImage] that attaches the user's Bearer token.
///
/// The chat-app serves `/api/images/<uuid>/view` (and a few other
/// asset endpoints) behind auth — without the header CachedNetworkImage's
/// internal HTTP client gets 401 and the image renders as the broken
/// placeholder. The token comes from [currentAccessTokenProvider]
/// which AuthRepository + AuthInterceptor keep in sync.
class AuthedNetworkImage extends ConsumerWidget {
  const AuthedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;

  /// Override the default placeholder (defaults to a soft shimmer-y
  /// surfaceContainer fill). Useful for hero / gallery layouts that
  /// want their own loading style.
  final Widget Function(BuildContext context, String url)? placeholder;

  /// Override the default error widget (broken-image icon on
  /// surfaceContainer fill).
  final Widget Function(BuildContext context, String url, Object error)?
      errorWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(currentAccessTokenProvider);
    final cs = Theme.of(context).colorScheme;
    // Sahachiel: only attach the Bearer to our own secure origin — never send
    // the access token to a third-party or cleartext image host.
    final sendToken = token != null && ApiConstants.isOwnOrigin(imageUrl);

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: sendToken ? {'Authorization': 'Bearer $token'} : null,
      // Cache key MUST include the token-ness so a sign-in / sign-out
      // doesn't render the previous user's token's image from cache.
      // Token value itself can rotate — keying on the URL is enough as
      // long as the per-user image UUID is unique.
      placeholder: (context, url) =>
          placeholder?.call(context, url) ??
          Container(color: cs.surfaceContainer),
      errorWidget: (context, url, error) =>
          errorWidget?.call(context, url, error) ??
          Container(
            color: cs.surfaceContainer,
            alignment: Alignment.center,
            child: Icon(
              Icons.broken_image_outlined,
              color: cs.onSurfaceVariant,
              size: 28,
            ),
          ),
    );
  }
}
