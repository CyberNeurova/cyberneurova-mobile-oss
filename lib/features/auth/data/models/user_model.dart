import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
class UserModel with _$UserModel {
  const factory UserModel({
    required String id,
    required String email,
    String? name,
    String? image,
    @Default(false) bool emailVerified,
    @Default(false) bool isPrivateRelay,
    @Default('free') String tier,
    SubscriptionModel? subscription,
    TokensModel? tokens,
    DateTime? createdAt,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
}

@freezed
class SubscriptionModel with _$SubscriptionModel {
  const factory SubscriptionModel({
    @Default('free') String tier,
    @Default('active') String status,
    DateTime? startDate,
    DateTime? endDate,
    @Default(false) bool isYearly,
  }) = _SubscriptionModel;

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionModelFromJson(json);
}

@freezed
class TokensModel with _$TokensModel {
  const factory TokensModel({
    @Default(0) int used,
    @Default(0) int limit,
    @Default(0) int remaining,
    DateTime? resetAt,
    String? billingCycle, // monthly | daily
  }) = _TokensModel;

  factory TokensModel.fromJson(Map<String, dynamic> json) =>
      _$TokensModelFromJson(json);
}

/// Successful login / register-via-OAuth / refresh response.
@freezed
class AuthTokensModel with _$AuthTokensModel {
  const factory AuthTokensModel({
    required String accessToken,
    required String refreshToken,
    @Default(3600) int expiresIn,
    UserModel? user,
    @Default(false) bool isNewUser,
  }) = _AuthTokensModel;

  factory AuthTokensModel.fromJson(Map<String, dynamic> json) =>
      _$AuthTokensModelFromJson(json);
}

/// Response from POST /auth/register — does NOT auto-login.
/// User must verify email before logging in.
@freezed
class RegisterResponse with _$RegisterResponse {
  const factory RegisterResponse({
    required String message,
    @Default(true) bool emailVerificationRequired,
  }) = _RegisterResponse;

  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      _$RegisterResponseFromJson(json);
}
