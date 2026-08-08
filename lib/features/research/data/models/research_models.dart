import 'package:freezed_annotation/freezed_annotation.dart';

part 'research_models.freezed.dart';
part 'research_models.g.dart';

/// One research session — a chat row tagged with a security category.
/// Always-on-PG storage; surfaced through `/research/sessions`.
@freezed
class ResearchSession with _$ResearchSession {
  const factory ResearchSession({
    @Default('') String id,
    @Default('') String title,
    @Default('') String category, // cve | exploit | bugbounty | malware | pentest
    @Default(0) int queryCount,
    DateTime? lastQueryAt,
    DateTime? createdAt,
  }) = _ResearchSession;

  // Arrow-body fromJson so json_serializable still generates `toJson` for this
  // type (ResearchListResponse needs it to serialize its List<ResearchSession>).
  // Key normalization lives in [normalize], applied by callers per element.
  factory ResearchSession.fromJson(Map<String, dynamic> json) =>
      _$ResearchSessionFromJson(json);

  /// The backend returns the id as `sessionId` (not `id`) and ships the full
  /// `queries` array instead of a `queryCount`. Normalize so the id is never
  /// empty (empty id = tapping a session can't open it) and the count is real.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      ...m,
      'id': m['id'] ?? m['sessionId'] ?? '',
      'queryCount': m['queryCount'] ??
          (m['queries'] is List ? (m['queries'] as List).length : 0),
    };
  }
}

/// One query inside a research session — the user prompt + assistant reply
/// + the web sources the AI cited.
@freezed
class ResearchQuery with _$ResearchQuery {
  const factory ResearchQuery({
    @Default('') String id,
    @Default('') String prompt,
    @Default('') String response,
    @Default([]) List<ResearchSource> sources,
    DateTime? createdAt,
  }) = _ResearchQuery;

  factory ResearchQuery.fromJson(Map<String, dynamic> json) =>
      _$ResearchQueryFromJson(json);
}

@freezed
class ResearchSource with _$ResearchSource {
  const factory ResearchSource({
    @Default('') String url,
    String? title,
    String? snippet,
    String? favicon,
  }) = _ResearchSource;

  factory ResearchSource.fromJson(Map<String, dynamic> json) =>
      _$ResearchSourceFromJson(json);
}

@freezed
class ResearchListResponse with _$ResearchListResponse {
  const factory ResearchListResponse({
    @Default([]) List<ResearchSession> sessions,
    String? nextCursor,
    @Default(false) bool hasMore,
  }) = _ResearchListResponse;

  // Constructs directly (freezed only generates json glue for the plain
  // arrow-redirect form; a normalizing body must build the object itself).
  factory ResearchListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['sessions'];
    final sessions = (raw is List ? raw : const [])
        .whereType<Map>()
        .map((s) => ResearchSession.fromJson(ResearchSession.normalize(s)))
        .toList();
    return ResearchListResponse(
      sessions: sessions,
      nextCursor: json['nextCursor'] is String ? json['nextCursor'] as String : null,
      hasMore: json['hasMore'] is bool ? json['hasMore'] as bool : false,
    );
  }
}

@freezed
class ResearchDetail with _$ResearchDetail {
  const factory ResearchDetail({
    required ResearchSession session,
    @Default([]) List<ResearchQuery> queries,
  }) = _ResearchDetail;

  /// API returns `{ session: { ...session fields..., queries: [...] } }`.
  /// We flatten so the widget tree gets a session + a queries list cleanly.
  factory ResearchDetail.fromApi(Map<String, dynamic> json) {
    // Sahachiel: defensive flatten. `session` may be the wrapper or absent (then
    // json IS the session), `queries` may be missing or wrong-typed, and a query
    // element may not be a map. Guard each instead of `as Map`/`as List` casts
    // that throw and crash the detail screen on a drifted payload.
    final rawSession = json['session'];
    final s = rawSession is Map
        ? Map<String, dynamic>.from(rawSession)
        : json;
    final rawQueries = s['queries'];
    final queries = rawQueries is List ? rawQueries : const [];
    return ResearchDetail(
      session: ResearchSession.fromJson(ResearchSession.normalize(s)),
      queries: queries
          .whereType<Map>()
          .map((q) => ResearchQuery.fromJson(Map<String, dynamic>.from(q)))
          .toList(),
    );
  }
}
