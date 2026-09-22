/// A device the user can attach to and drive remotely — a running desktop /
/// CLI session (mobile is the CONTROLLER). Defensively parsed like the bot
/// models: unknown/half-shaped rows are skipped, not thrown on.
///
/// Contract: chat `collaborationdir/mobile/chat/2026-08-29-0840-relay-endpoints-specced.md`.
/// `attachUrl` is **precomputed by the relay — use it verbatim**, never string-built.
class RemoteDevice {
  const RemoteDevice({
    required this.deviceId,
    required this.kind,
    this.label,
    this.online = false,
    this.lastSeen,
    this.attachUrl,
  });

  final String deviceId;

  /// `desktop` | `cli` | … (what kind of executor this is).
  final String kind;
  final String? label;
  final bool online;
  final String? lastSeen;

  /// The relay page to open in the attach webview. Precomputed server-side.
  final String? attachUrl;

  bool get canAttach => (attachUrl?.isNotEmpty ?? false);

  static RemoteDevice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String? str(String a, [String? b]) {
      final v = raw[a] ?? (b != null ? raw[b] : null);
      return v is String && v.isNotEmpty ? v : null;
    }

    final id = str('device_id', 'deviceId');
    if (id == null) return null;
    return RemoteDevice(
      deviceId: id,
      kind: str('kind') ?? 'device',
      label: str('label'),
      online: raw['online'] == true,
      lastSeen: str('last_seen', 'lastSeen'),
      attachUrl: str('attach_url', 'attachUrl'),
    );
  }

  /// Parses `{ devices: [...] }` (or a bare list).
  static List<RemoteDevice> listFrom(Object? raw) {
    final list = raw is Map ? raw['devices'] : raw;
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (tryParse(e) case final d?) d,
    ];
  }
}
