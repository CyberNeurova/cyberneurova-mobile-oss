import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One thing found on the network.
class MdnsService {
  const MdnsService({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
  });

  /// What the device calls itself — "Living Room TV", "brother-printer".
  final String name;

  /// `_googlecast._tcp`, `_ssh._tcp`, …
  final String type;

  final String host;
  final int port;

  /// A one-line form for a tool result.
  String get line => '$host:$port  $name  ($type)';

  static MdnsService? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final host = raw['host'];
    final port = raw['port'];
    if (host is! String || host.isEmpty || port is! int) return null;
    return MdnsService(
      name: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? raw['name'] as String
          : host,
      type: (raw['type'] as String?) ?? '',
      host: host,
      port: port,
    );
  }
}

/// Asking the network what is on it.
///
/// ## Why this is a platform channel
///
/// mDNS is multicast on 224.0.0.251:5353, and Dart's `RawDatagramSocket` cannot
/// join a multicast group with the socket options it exposes on Android. That
/// is why `MDNS_DISCOVERY` sat in the MISSING list from the day the capability
/// set was written — not an oversight, a real gap that only native code closes.
///
/// ## Why it is worth closing
///
/// A port scan says 192.168.1.31:8009 is open. mDNS says that box calls itself
/// "Living Room TV" and speaks `_googlecast._tcp`. For an agent deciding what
/// to do next, the second is a fact and the first is a guess — and neither our
/// servers nor any container can obtain it, because it never leaves the user's
/// own network segment.
class Mdns {
  const Mdns._();

  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('ai.cyberneurova.app/device_runtime');

  /// Browses for [timeout] and returns what resolved.
  ///
  /// Never throws. A network with nothing on it, a device that refuses
  /// multicast, and a build with no platform side are all the same ordinary
  /// answer: an empty list.
  static Future<List<MdnsService>> discover({
    Duration timeout = const Duration(seconds: 5),
    List<String> types = const [],
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final raw = await channel.invokeListMethod<Object?>('mdnsDiscover', {
        'timeoutMs': timeout.inMilliseconds,
        'types': types,
      });
      if (raw == null) return const [];
      final out = <MdnsService>[];
      for (final e in raw) {
        final service = MdnsService.fromMap(e);
        if (service != null) out.add(service);
      }
      return out;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
