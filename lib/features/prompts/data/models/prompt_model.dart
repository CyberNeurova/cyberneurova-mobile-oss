import 'package:freezed_annotation/freezed_annotation.dart';

part 'prompt_model.freezed.dart';
part 'prompt_model.g.dart';

@freezed
class PromptModel with _$PromptModel {
  const factory PromptModel({
    required String id,
    required String title,
    required String content,
    String? icon, // optional emoji or icon name
    @Default(false) bool isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _PromptModel;

  factory PromptModel.fromJson(Map<String, dynamic> json) =>
      _$PromptModelFromJson(json);

  /// Backend stores the label under `name` (not `title`) and may key the id as
  /// `_id`/`promptId`. Coalesce so the required fields are never null (which
  /// would throw inside fromJson and blank the Custom Prompts screen).
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      ...m,
      'id': m['id'] ?? m['_id'] ?? m['promptId'] ?? '',
      'title': m['title'] ?? m['name'] ?? '',
      'content': m['content'] ?? '',
    };
  }
}
