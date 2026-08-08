import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_model.freezed.dart';
part 'memory_model.g.dart';

@freezed
class MemoryModel with _$MemoryModel {
  const factory MemoryModel({
    required String id,
    required String content,
    @Default('context') String category, // preference|fact|project|pattern|context
    @Default(3) int importance, // 1..5
    @Default(0) int accessCount,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
  }) = _MemoryModel;

  factory MemoryModel.fromJson(Map<String, dynamic> json) =>
      _$MemoryModelFromJson(json);

  /// Defensive id/content coalescing in case the backend keys drift
  /// (`_id`/`memoryId`, `text`) — keeps a row from throwing the whole list.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      ...m,
      'id': m['id'] ?? m['_id'] ?? m['memoryId'] ?? '',
      'content': m['content'] ?? m['text'] ?? '',
    };
  }
}

/// Aggregate stats over the user's memories. Shipped with `/memory` GET as
/// of chat-app round 3. Lets us render the tracker UI without recomputing
/// from the list client-side.
@freezed
class MemoryTracker with _$MemoryTracker {
  const factory MemoryTracker({
    @Default({}) Map<String, int> categoryCounts,
    DateTime? oldestAt,
    DateTime? newestAt,
    DateTime? lastExtractedAt,
    @Default(0.0) double averageImportance,
    @Default(false) bool atCapacity,
  }) = _MemoryTracker;

  factory MemoryTracker.fromJson(Map<String, dynamic> json) =>
      _$MemoryTrackerFromJson(json);
}

@freezed
class MemoryListResponse with _$MemoryListResponse {
  const factory MemoryListResponse({
    @Default([]) List<MemoryModel> memories,
    @Default(0) int count,
    @Default(100) int limit,
    MemoryTracker? tracker,
    String? nextCursor,
    @Default(false) bool hasMore,
  }) = _MemoryListResponse;

  // Constructs directly: the real payload nests everything under `data`
  // ({success, data:{memories[], count, limit, tracker}}); unwrap it first,
  // then coalesce the list key, normalize + skip bad rows.
  factory MemoryListResponse.fromJson(Map<String, dynamic> json) {
    final d = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final raw = d['memories'] ?? d['items'];
    final memories = <MemoryModel>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          try {
            memories.add(MemoryModel.fromJson(MemoryModel.normalize(e)));
          } catch (_) {/* skip malformed row */}
        }
      }
    }
    final tracker = d['tracker'];
    return MemoryListResponse(
      memories: memories,
      count: d['count'] is int ? d['count'] as int : memories.length,
      limit: d['limit'] is int ? d['limit'] as int : 100,
      tracker: tracker is Map
          ? MemoryTracker.fromJson(Map<String, dynamic>.from(tracker))
          : null,
      nextCursor: d['nextCursor'] is String ? d['nextCursor'] as String : null,
      hasMore: d['hasMore'] is bool ? d['hasMore'] as bool : false,
    );
  }
}
