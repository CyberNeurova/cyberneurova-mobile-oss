import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:cyberneurova_mobile/core/constants/app_constants.dart';

part 'model_info.freezed.dart';
part 'model_info.g.dart';

/// Per-model capability set returned by `/api/mobile/v1/models`
/// (chat-team inbox/020). All fields default to `false` so the UI is
/// pessimistic about unknown models — better to hide an attach button
/// than to show it and surprise the user with a 403 TIER_REQUIRED.
@freezed
class ModelCapabilities with _$ModelCapabilities {
  const factory ModelCapabilities({
    @Default(false) bool vision,
    @Default(false) bool fileUpload,
    @Default(false) bool reasoning,
  }) = _ModelCapabilities;

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) =>
      _$ModelCapabilitiesFromJson(json);
}

@freezed
class ModelInfo with _$ModelInfo {
  const ModelInfo._();

  const factory ModelInfo({
    // Defaulted (not required) so a single drifted/partial entry in /models
    // can't throw and take down the whole model picker; ModelsResponse drops
    // any entry left with a blank id.
    @Default('') String id,
    @Default('') String name,
    String? description,
    @Default(true) bool available,
    // Added 2026-06-17 per chat-team inbox/020. All nullable so older
    // builds don't blow up on missing fields and so we can still parse
    // historical /models responses cached locally.
    int? contextWindow,
    double? charsPerToken,
    int? maxOutputTokens,
    ModelCapabilities? capabilities,
  }) = _ModelInfo;

  factory ModelInfo.fromJson(Map<String, dynamic> json) =>
      _$ModelInfoFromJson(json);

  // Gate UI on these (not on `capabilities` directly) so the absent-block
  // case — older server builds — collapses to "feature off" in one place.
  bool get supportsVision => capabilities?.vision ?? false;
  bool get supportsFileUpload => capabilities?.fileUpload ?? false;
  bool get supportsReasoning => capabilities?.reasoning ?? false;
}

@freezed
class ModelsResponse with _$ModelsResponse {
  const factory ModelsResponse({
    @Default([]) List<ModelInfo> models,
    @Default([]) List<ModelInfo> locked,
    // Literal rather than AppConstants.kFallbackModelId because freezed copies
    // this into model_info.freezed.dart; keep the two in sync.
    @Default('cyberneurova-gemma') String defaultModel,
  }) = _ModelsResponse;

  // Constructs directly: parse each entry defensively and drop blank-id ones so
  // one malformed model can't error the whole picker (chat-critical path).
  factory ModelsResponse.fromJson(Map<String, dynamic> json) {
    List<ModelInfo> parse(dynamic raw) {
      final out = <ModelInfo>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            try {
              final m = ModelInfo.fromJson(Map<String, dynamic>.from(e));
              if (m.id.isNotEmpty) out.add(m);
            } catch (_) {
              // Skip a malformed model rather than failing the list.
            }
          }
        }
      }
      return out;
    }

    return ModelsResponse(
      models: parse(json['models']),
      locked: parse(json['locked']),
      defaultModel: json['defaultModel'] is String
          ? json['defaultModel'] as String
          : AppConstants.kFallbackModelId,
    );
  }
}
