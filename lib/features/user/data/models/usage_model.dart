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

  /// Normalises a `/user/usage` payload for the generated [fromJson].
  ///
  /// The generated parser casts every field to its declared type and throws on
  /// anything else — a fractional token count, an epoch-number `resetAt`, a
  /// bucket that is not an object. That throw never reaches the user as an
  /// error: the Usage screen reads `valueOrNull?.legacy ?? true`, so a v2
  /// account silently drops its breakdown and gets the legacy "Tokens 0 / 60M"
  /// card, which reads a counter that is not the one filling. Coerce what can
  /// be read and drop what can't, so one drifted field costs that field and
  /// not the whole screen.
  static Map<String, dynamic> sanitize(Map<dynamic, dynamic> raw) {
    return <String, dynamic>{
      'schemaVersion': _asInt(raw['schemaVersion'], 2),
      if (raw['tier'] is String) 'tier': raw['tier'],
      if (raw['billingCycle'] is String) 'billingCycle': raw['billingCycle'],
      if (raw['legacy'] is bool) 'legacy': raw['legacy'],
      'session': UsageBucket.sanitize(raw['session']),
      'weekly': UsageBucket.sanitize(raw['weekly']),
      'weeklyPremium': UsageBucket.sanitize(raw['weeklyPremium']),
      'extraUnits': UsageExtras.sanitize(raw['extraUnits']),
      'tierReference': TierReference.sanitize(raw['tierReference']),
      'message': raw['message'] is String ? raw['message'] : null,
    };
  }
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

  /// See [UsageDetail.sanitize]. Null when the bucket is not an object.
  static Map<String, dynamic>? sanitize(Object? raw) {
    if (raw is! Map) return null;
    return <String, dynamic>{
      'used': _asInt(raw['used'], 0),
      'limit': _asInt(raw['limit'], 0),
      'remaining': _asInt(raw['remaining'], 0),
      'percentUsed': _asDouble(raw['percentUsed'], 0.0),
      'resetAt': _asIsoDate(raw['resetAt']),
    };
  }
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

  /// See [UsageDetail.sanitize]. Null when the value is not an object.
  static Map<String, dynamic>? sanitize(Object? raw) {
    if (raw is! Map) return null;
    return <String, dynamic>{
      'remaining': _asInt(raw['remaining'], 0),
      'spentUsdLifetime': _asDouble(raw['spentUsdLifetime'], 0.0),
      'spentUsdThisMonth': _asDouble(raw['spentUsdThisMonth'], 0.0),
      'monthlyCapUsd': _asDouble(raw['monthlyCapUsd'], 0.0),
      if (raw['autoReload'] is bool) 'autoReload': raw['autoReload'],
      'monthResetAt': _asIsoDate(raw['monthResetAt']),
    };
  }
}

@freezed
class TierReference with _$TierReference {
  const factory TierReference({
    @Default(0) int tokensPerPeriod,
  }) = _TierReference;

  factory TierReference.fromJson(Map<String, dynamic> json) =>
      _$TierReferenceFromJson(json);

  /// See [UsageDetail.sanitize]. Null when the value is not an object.
  static Map<String, dynamic>? sanitize(Object? raw) {
    if (raw is! Map) return null;
    return <String, dynamic>{
      'tokensPerPeriod': _asInt(raw['tokensPerPeriod'], 0),
    };
  }
}

/// A count however the server sent it — int, double (truncated) or numeric
/// string. Anything else, including a non-finite value, is [fallback]: the
/// field's own default.
int _asInt(Object? v, int fallback) {
  final n = v is String ? num.tryParse(v.trim()) : v;
  return n is num && n.isFinite ? n.toInt() : fallback;
}

double _asDouble(Object? v, double fallback) {
  final n = v is String ? num.tryParse(v.trim()) : v;
  return n is num && n.isFinite ? n.toDouble() : fallback;
}

/// An ISO-8601 timestamp the generated parser can read, or null. An epoch
/// number is not converted: it could be seconds or milliseconds, and a guessed
/// reset date is worse than none — the screen just omits it.
String? _asIsoDate(Object? v) =>
    v is String && DateTime.tryParse(v) != null ? v : null;
