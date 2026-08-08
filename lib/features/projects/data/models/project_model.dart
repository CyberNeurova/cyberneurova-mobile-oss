import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_model.freezed.dart';
part 'project_model.g.dart';

@freezed
class ProjectModel with _$ProjectModel {
  const factory ProjectModel({
    required String id,
    required String name,
    String? description,
    String? icon,
    String? color,
    @Default(0) int chatCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _ProjectModel;

  factory ProjectModel.fromJson(Map<String, dynamic> json) =>
      _$ProjectModelFromJson(json);

  /// Coalesce id/name (in case the backend keys as `_id`/`projectId`/`title`)
  /// and derive chatCount from a `chats`/`chatIds` array if a count isn't sent.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    final chats = m['chats'] ?? m['chatIds'];
    return <String, dynamic>{
      ...m,
      'id': m['id'] ?? m['_id'] ?? m['projectId'] ?? '',
      'name': m['name'] ?? m['title'] ?? '',
      'chatCount': m['chatCount'] ?? (chats is List ? chats.length : 0),
    };
  }
}
