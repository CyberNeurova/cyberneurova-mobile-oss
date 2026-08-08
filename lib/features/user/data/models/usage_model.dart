import 'package:freezed_annotation/freezed_annotation.dart';

part 'usage_model.freezed.dart';
part 'usage_model.g.dart';

/// Per-period token usage. Most accounts are v2 (session/weekly/weeklyPremium).
/// Legacy daily-tokens accounts return schemaVersion=1 → caller falls back
/// to the existing /user/tokens shape via UserModel.tokens.
@freezed
class UsageDetail with _$UsageDetail {
  const factory UsageDetail({
    @Default(2) int schemaVersion,
    @Default('free') String tier,
    @Default('monthly') String billingCycle,
    @Default(false) bool legacy,
    UsageBucket? session,
    UsageBucket? weekly,
    UsageBucket? weeklyPremium,
    UsageExtras? extraUnits,
    TierReference? tierReference,
    String? message,
  }) = _UsageDetail;

  factory UsageDetail.fromJson(Map<String, dynamic> json) =>
      _$UsageDetailFromJson(json);
}

@freezed
class UsageBucket with _$UsageBucket {
  const factory UsageBucket({
    @Default(0) int used,
    @Default(0) int limit,
    @Default(0) int remaining,
    @Default(0.0) double percentUsed,
    DateTime? resetAt,
  }) = _UsageBucket;

  factory UsageBucket.fromJson(Map<String, dynamic> json) =>
      _$UsageBucketFromJson(json);
}

@freezed
class UsageExtras with _$UsageExtras {
  const factory UsageExtras({
    @Default(0) int remaining,
    @Default(0.0) double spentUsdLifetime,
    @Default(0.0) double spentUsdThisMonth,
    @Default(0.0) double monthlyCapUsd,
    @Default(false) bool autoReload,
    DateTime? monthResetAt,
  }) = _UsageExtras;

  factory UsageExtras.fromJson(Map<String, dynamic> json) =>
      _$UsageExtrasFromJson(json);
}

@freezed
class TierReference with _$TierReference {
  const factory TierReference({
    @Default(0) int tokensPerPeriod,
  }) = _TierReference;

  factory TierReference.fromJson(Map<String, dynamic> json) =>
      _$TierReferenceFromJson(json);
}
