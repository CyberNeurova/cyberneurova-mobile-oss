import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/capabilities/data/models/capability_models.dart';

final capabilitiesRepositoryProvider =
    Provider<CapabilitiesRepository>((ref) {
  return CapabilitiesRepository(ref.watch(apiClientProvider));
});

/// Unified accessor for Skills and Tools — both routes share shape so we
/// have one repo with two methods each (list + toggle).
class CapabilitiesRepository {
  CapabilitiesRepository(this._client);
  final ApiClient _client;

  // ─── Skills ─────────────────────────────────────────────────────────────
  Future<CapabilityListResponse> listSkills() async {
    final res = await _client.get<Map<String, dynamic>>(
      ApiConstants.SKILLS,
    );
    return CapabilityListResponse.fromJson(res.data!, 'skills');
  }

  /// Skills toggle is per-id via POST to `/skills/:id`.
  /// The route accepts an empty body and flips the user's enabled list.
  Future<void> toggleSkill(String id, bool enabled) async {
    await _client.post(
      ApiConstants.skillToggle(id),
      data: {'enabled': enabled},
    );
  }

  // ─── Tools ──────────────────────────────────────────────────────────────
  Future<CapabilityListResponse> listTools() async {
    final res = await _client.get<Map<String, dynamic>>('/tools');
    return CapabilityListResponse.fromJson(res.data!, 'tools');
  }

  /// Tools toggle is PATCH `/tools` with `{toolId, enabled}` body.
  Future<void> toggleTool(String toolId, bool enabled) async {
    await _client.patch(
      '/tools',
      data: {'toolId': toolId, 'enabled': enabled},
    );
  }
}
