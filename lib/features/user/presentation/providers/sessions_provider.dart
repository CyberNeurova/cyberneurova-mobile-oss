import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/shared/collections/optimistic_revert.dart';
import 'package:cyberneurova_mobile/features/auth/data/repositories/auth_repository.dart';

class SessionEntry {
  const SessionEntry({
    required this.id,
    required this.deviceName,
    required this.platform,
    this.location,
    this.lastUsedAt,
    this.isCurrent = false,
  });

  final String id;
  final String deviceName;
  final String platform; // ios | android | web
  final String? location;
  final DateTime? lastUsedAt;
  final bool isCurrent;

  factory SessionEntry.fromJson(Map<String, dynamic> json) => SessionEntry(
        // Real contract (MOBILE_API.md): {sessionId, source, deviceName,
        // deviceType, ipAddress(masked), lastActivityAt, createdAt, isCurrent}.
        // Coalesce so revoke (keyed on id=sessionId) and the row labels work.
        id: json['sessionId'] as String? ?? json['id'] as String? ?? '',
        deviceName: json['deviceName'] as String? ??
            json['userAgent'] as String? ??
            '—',
        platform: json['deviceType'] as String? ??
            json['source'] as String? ??
            json['platform'] as String? ??
            'unknown',
        location: json['ipAddress'] as String? ?? json['location'] as String?,
        lastUsedAt: DateTime.tryParse(
            (json['lastActivityAt'] ?? json['createdAt'] ?? json['lastUsedAt'])
                    ?.toString() ??
                ''),
        isCurrent: json['isCurrent'] as bool? ?? false,
      );
}

final sessionsProvider =
    AsyncNotifierProvider<SessionsNotifier, List<SessionEntry>>(
  SessionsNotifier.new,
);

class SessionsNotifier extends AsyncNotifier<List<SessionEntry>> {
  @override
  Future<List<SessionEntry>> build() async {
    final raw = await ref.read(authRepositoryProvider).listSessions();
    return raw.map(SessionEntry.fromJson).toList();
  }

  Future<void> revoke(String sessionId) async {
    final current = state.valueOrNull ?? [];
    final wasAt = positionOf(current, (s) => s.id == sessionId);
    if (wasAt < 0) return;
    final removed = current[wasAt];
    // Optimistically remove
    state = AsyncData(current.where((s) => s.id != sessionId).toList());
    try {
      await ref.read(authRepositoryProvider).revokeSession(sessionId);
    } catch (_) {
      // Put back only this session. Restoring the whole pre-request snapshot
      // also un-revoked any other session signed out while this call was in
      // flight — and on this screen that is the difference between "I removed
      // that device" and finding it listed again.
      state =
          AsyncData(restoreAt(state.valueOrNull ?? current, removed, wasAt));
      rethrow;
    }
  }

  // Sahachiel: revoke every session except the one on this device. The mobile
  // API has no per-id route — it's the collection DELETE with {revokeAll:true}
  // (OPEN_ISSUES #21). Optimistically keep only the current session.
  Future<void> revokeAllOthers() async {
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((s) => s.isCurrent).toList());
    try {
      await ref.read(authRepositoryProvider).revokeAllOtherSessions();
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}
