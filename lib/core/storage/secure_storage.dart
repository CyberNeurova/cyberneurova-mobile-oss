import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';

final secureStorageProvider = Provider<SecureStorage>((ref) => SecureStorage());

/// Synchronously-readable mirror of the access token so widgets like
/// [CachedNetworkImage] can attach a Bearer header without an async
/// FutureBuilder. Updated by [AuthRepository] on login/logout/refresh
/// and rehydrated at app startup from secure storage. Never persist
/// here — secure storage is authoritative.
final currentAccessTokenProvider = StateProvider<String?>((_) => null);

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.kAccessToken, value: accessToken),
      _storage.write(key: AppConstants.kRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> getAccessToken() =>
      _storage.read(key: AppConstants.kAccessToken);

  Future<String?> getRefreshToken() =>
      _storage.read(key: AppConstants.kRefreshToken);

  Future<void> clearAll() => _storage.deleteAll();
}
