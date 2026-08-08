import 'dart:io';

/// Resolves the subnets this device is currently attached to.
///
/// `include_local_subnet` in a session scope resolves through here at call
/// time rather than being captured once. That is deliberate: "scan my
/// network" should follow the user onto a new Wi-Fi network, and — more
/// importantly — should *stop* authorising the old one the moment they leave
/// it. A cached CIDR would keep a stale authorisation alive.
class LocalNetwork {
  /// Private-range IPv4 subnets of the active interfaces, as CIDRs.
  ///
  /// Only RFC1918 addresses are returned. A public address on an interface is
  /// not "my network" in any sense that should authorise scanning it.
  ///
  /// Returns an empty list when nothing usable is found, which callers must
  /// treat as "unknown" rather than "none" — the tools ask for an explicit
  /// CIDR instead of guessing.
  static Future<List<String>> subnets() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      final out = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final cidr = _privateSubnetOf(addr.address);
          if (cidr != null) out.add(cidr);
        }
      }
      return out.toList();
    } on SocketException {
      // Permission denied or no interfaces — indistinguishable here, and
      // both mean "we don't know".
      return const [];
    }
  }

  /// This device's own private IPv4 address(es) — the answer to "what's my IP".
  ///
  /// [subnets] deliberately throws the host octet away to authorise a whole
  /// /24; this keeps it, because a model asked for the device's address should
  /// be handed it rather than shelling out — and under PRoot the shell cannot
  /// read the network namespace, so `ip addr`/`hostname -I` return nothing and
  /// the model loops on them. Same RFC1918-only filter: a public address on an
  /// interface is not reported. Empty means "unknown", not "none".
  static Future<List<String>> selfPrivateIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      final out = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_privateSubnetOf(addr.address) != null) out.add(addr.address);
        }
      }
      return out.toList();
    } on SocketException {
      return const [];
    }
  }

  /// Assumes /24, which is right for essentially every consumer LAN and is
  /// the only size the TCP-probe discovery tool will expand anyway.
  static String? _privateSubnetOf(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final nums = [for (final p in parts) int.tryParse(p)];
    if (nums.any((n) => n == null || n < 0 || n > 255)) return null;

    final a = nums[0]!, b = nums[1]!;
    final isPrivate = a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
    if (!isPrivate) return null;

    return '${nums[0]}.${nums[1]}.${nums[2]}.0/24';
  }
}
