import 'package:freezed_annotation/freezed_annotation.dart';

part 'capability_models.freezed.dart';
part 'capability_models.g.dart';

/// A skill or a tool — both routes return the same logical shape so we use
/// one model. `kind` distinguishes them. `requiredTier` is `free` /
/// `premium` / `pro` / `pro_max`. `accessible` is true if the user's current
/// tier is at-or-above `requiredTier`.
@freezed
class CapabilityModel with _$CapabilityModel {
  const factory CapabilityModel({
    @Default('') String id,
    @Default('') String name,
    String? description,
    String? type, // builtin | custom (or skill-specific category)
    @Default(false) bool enabled,
    @Default('free') String requiredTier,
    @Default(true) bool accessible,
    Map<String, dynamic>? config,
  }) = _CapabilityModel;

  factory CapabilityModel.fromJson(Map<String, dynamic> json) =>
      _$CapabilityModelFromJson(json);

  /// /tools returns `enabled`/`type`; /skills returns `isEnabled`/`category`.
  /// Coalesce both so the toggle state + category render for either route.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      ...m,
      'enabled': m['enabled'] ?? m['isEnabled'] ?? false,
      'type': m['type'] ?? m['category'],
    };
  }
}

@freezed
class CapabilityListResponse with _$CapabilityListResponse {
  const factory CapabilityListResponse({
    @Default([]) List<CapabilityModel> items,
  }) = _CapabilityListResponse;

  /// `/skills` returns `{skills: [...]}`, `/tools` returns `{tools: [...]}`.
  /// Pass the key when calling.
  factory CapabilityListResponse.fromJson(
    Map<String, dynamic> json,
    String key,
  ) {
    // Sahachiel: tolerate a missing/wrong-typed list and non-map elements rather
    // than `as List` / `as Map` casts that throw and blank the whole screen.
    final raw = json[key];
    final list = raw is List ? raw : const [];
    return CapabilityListResponse(
      items: list
          .whereType<Map>()
          .map((j) => CapabilityModel.fromJson(CapabilityModel.normalize(j)))
          .toList(),
    );
  }
}
