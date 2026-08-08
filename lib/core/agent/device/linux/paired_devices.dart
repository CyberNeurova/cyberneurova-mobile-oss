import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A device this app has paired with over ADB.
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.firstPairedAt,
    required this.lastConnectedAt,
    this.uid,
  });

  /// Stable key. The device's own name is not stable — people rename phones —
  /// so pairings are keyed on what we connected to instead.
  final String id;

  final String name;

  /// The uid the shell ran as, when we know it. 2000 is ADB's, 0 is root.
  ///
  /// Worth remembering: it is the difference between "can install apps" and
  /// "can do anything", and a user reviewing what they have granted should not
  /// have to reconnect to find out which one they said yes to.
  final String? uid;

  final DateTime firstPairedAt;
  final DateTime lastConnectedAt;

  PairedDevice copyWith({String? name, String? uid, DateTime? lastConnectedAt}) =>
      PairedDevice(
        id: id,
        name: name ?? this.name,
        uid: uid ?? this.uid,
        firstPairedAt: firstPairedAt,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (uid != null) 'uid': uid,
        'firstPairedAt': firstPairedAt.toIso8601String(),
        'lastConnectedAt': lastConnectedAt.toIso8601String(),
      };

  /// Returns null for an entry we cannot read, so one bad record cannot take
  /// the whole list down — the same rule the model lists follow.
  static PairedDevice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final first = DateTime.tryParse(raw['firstPairedAt'] as String? ?? '');
    final last = DateTime.tryParse(raw['lastConnectedAt'] as String? ?? '');
    if (first == null || last == null) return null;
    return PairedDevice(
      id: id,
      name: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? raw['name'] as String
          : id,
      uid: raw['uid'] as String?,
      firstPairedAt: first,
      lastConnectedAt: last,
    );
  }
}

/// Everything this app has ever paired with.
///
/// ## Why keep a list at all
///
/// Pairing grants a shell that can install and remove apps. That is a real
/// grant, and the honest thing is to let someone see what they have handed out
/// and take it back — without having to remember what they did weeks ago.
///
/// The key on disk already survives reboots and the wireless-debugging toggle,
/// so without a record the user's only evidence of a pairing is that things
/// mysteriously work. A list makes it reviewable.
///
/// ## Newest first, and "first paired" is kept
///
/// The date that matters when reviewing a grant is when it was made, not when
/// it was last used — "I paired this in June" is the thing someone recognises
/// or does not. Both are stored, and the ordering is by recency because that
/// is what the list is scanned for.
class PairedDevices {
  const PairedDevices._();

  static const _key = 'adb_paired_devices_v1';

  static Future<List<PairedDevice>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <PairedDevice>[];
      for (final e in decoded) {
        final device = PairedDevice.fromJson(e);
        if (device != null) out.add(device);
      }
      out.sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Records a successful connection.
  ///
  /// Idempotent by [id]: reconnecting updates the timestamp and the uid rather
  /// than adding a duplicate, so a device used daily appears once.
  static Future<void> remember({
    required String id,
    required String name,
    String? uid,
    DateTime? at,
  }) async {
    if (id.trim().isEmpty) return;
    final now = at ?? DateTime.now();
    final existing = await all();

    final updated = <PairedDevice>[];
    var found = false;
    for (final d in existing) {
      if (d.id == id) {
        found = true;
        updated.add(d.copyWith(
          name: name,
          // Only overwrite a known uid with another known one. A connection
          // that could not report it must not erase what we already knew.
          uid: uid ?? d.uid,
          lastConnectedAt: now,
        ));
      } else {
        updated.add(d);
      }
    }
    if (!found) {
      updated.add(PairedDevice(
        id: id,
        name: name,
        uid: uid,
        firstPairedAt: now,
        lastConnectedAt: now,
      ));
    }

    await _write(updated);
  }

  /// Drops one entry. Does NOT unpair — see the note in the UI.
  static Future<void> forget(String id) async {
    final remaining = [
      for (final d in await all())
        if (d.id != id) d,
    ];
    await _write(remaining);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _write(List<PairedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final d in devices) d.toJson()]),
    );
  }
}
