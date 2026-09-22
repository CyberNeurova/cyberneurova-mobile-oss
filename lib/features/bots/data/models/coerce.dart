/// Defensive JSON coercion for the bot-section models.
///
/// Same assumption as [AgentFrame] (`core/agent/agent_frame.dart`): the
/// bot-section backend schema will drift ahead of the client, so every field
/// is *coerced*, never cast — a wrong-typed field degrades that one value
/// instead of throwing the whole object away.
library;

import 'dart:convert';

String? asString(Object? v) => v is String ? v : null;

String asStringOr(Object? v, String fallback) => v is String ? v : fallback;

int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool asBool(Object? v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is String) return v == 'true' || v == '1';
  if (v is num) return v != 0;
  return fallback;
}

Map<String, dynamic>? asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.isNotEmpty) {
    // Some backends double-encode nested objects as a JSON string.
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

List<Object?> asList(Object? v) => v is List ? v : const [];

List<String> asStringList(Object? v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is String) e,
  ];
}
