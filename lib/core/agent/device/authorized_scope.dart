/// What a session is allowed to touch.
///
/// From `docs/shell/00-OVERVIEW.md` AD-6: *"Any tool that emits packets at a
/// target takes a `target` argument checked against the session's authorized
/// scope list. Out-of-scope targets are refused by the executor, not merely
/// discouraged in the system prompt."*
///
/// This is the client-side half. The server evaluates scope too and its
/// verdict is authoritative, but the device re-checks before executing
/// anything — a replayed or tampered frame must not be able to point the
/// phone at a host the user never authorised. A prompt-level restriction is
/// not a control surface; this is.
///
/// Empty scope means only the device itself is targetable, which is a safe
/// and useful default for exploring.
class AuthorizedScope {
  const AuthorizedScope({
    this.cidrs = const [],
    this.hostPatterns = const [],
    this.includeLocalSubnet = false,
    this.note,
  });

  const AuthorizedScope.empty() : this();

  /// IPv4 CIDR blocks, e.g. `192.168.1.0/24`.
  final List<String> cidrs;

  /// Hostnames, optionally wildcarded: `*.lab.example.com`.
  final List<String> hostPatterns;

  /// Resolves at call time from the current interface, so "scan my network"
  /// works without typing a CIDR — and correctly stops working when the user
  /// changes networks.
  final bool includeLocalSubnet;

  /// Engagement reference or client name, recorded with the run.
  final String? note;

  bool get isEmpty =>
      cidrs.isEmpty && hostPatterns.isEmpty && !includeLocalSubnet;

  /// Whether [target] may be contacted.
  ///
  /// [localSubnetCidrs] is supplied by the caller from live interface state
  /// rather than read here, so this stays pure and testable.
  ScopeVerdict check(String target, {List<String> localSubnetCidrs = const []}) {
    final t = target.trim().toLowerCase();
    if (t.isEmpty) {
      return const ScopeVerdict.denied('No target given.');
    }

    // Loopback and the device itself are always in scope — that is what
    // makes an empty scope usable rather than inert.
    if (_isLoopback(t)) return const ScopeVerdict.allowed();

    final ip = _parseIpv4(t);

    if (ip != null) {
      for (final cidr in cidrs) {
        if (_ipInCidr(ip, cidr)) return const ScopeVerdict.allowed();
      }
      if (includeLocalSubnet) {
        for (final cidr in localSubnetCidrs) {
          if (_ipInCidr(ip, cidr)) return const ScopeVerdict.allowed();
        }
      }
      return ScopeVerdict.denied(
        '$target is outside the authorized scope for this session.',
      );
    }

    // Hostname.
    for (final pattern in hostPatterns) {
      if (_hostMatches(t, pattern.trim().toLowerCase())) {
        return const ScopeVerdict.allowed();
      }
    }
    return ScopeVerdict.denied(
      '$target is outside the authorized scope for this session.',
    );
  }

  /// A CIDR target (`192.168.1.0/24`) is in scope only when the whole block
  /// is covered — approving a sweep of a range the user did not authorise
  /// because one address inside it matched would defeat the point.
  ScopeVerdict checkRange(String cidr,
      {List<String> localSubnetCidrs = const []}) {
    final parsed = _parseCidr(cidr);
    if (parsed == null) {
      return check(cidr, localSubnetCidrs: localSubnetCidrs);
    }
    final allowed = [
      ...cidrs,
      if (includeLocalSubnet) ...localSubnetCidrs,
    ];
    for (final a in allowed) {
      final outer = _parseCidr(a);
      if (outer == null) continue;
      // Contained when the outer block is no more specific and the target's
      // network address falls inside it.
      if (outer.prefix <= parsed.prefix &&
          _ipInCidr(parsed.network, a)) {
        return const ScopeVerdict.allowed();
      }
    }
    return ScopeVerdict.denied(
      '$cidr is outside the authorized scope for this session.',
    );
  }

  Map<String, dynamic> toJson() => {
        'cidrs': cidrs,
        'hostnames': hostPatterns,
        'include_local_subnet': includeLocalSubnet,
        if (note != null) 'note': note,
      };

  /// Human-readable line for the session header and the prompt block.
  String describe() {
    if (isEmpty) return 'this device only';
    return [
      if (includeLocalSubnet) 'local subnet',
      ...cidrs,
      ...hostPatterns,
    ].join(', ');
  }

  static bool _isLoopback(String t) =>
      t == 'localhost' ||
      t == '127.0.0.1' ||
      t == '::1' ||
      t.startsWith('127.');

  static bool _hostMatches(String host, String pattern) {
    if (pattern == host) return true;
    if (pattern.startsWith('*.')) {
      final suffix = pattern.substring(1); // ".example.com"
      return host.endsWith(suffix) && host.length > suffix.length;
    }
    return false;
  }

  static int? _parseIpv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final p in parts) {
      final octet = int.tryParse(p);
      if (octet == null || octet < 0 || octet > 255) return null;
      value = (value << 8) | octet;
    }
    return value;
  }

  static ({int network, int prefix})? _parseCidr(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final base = _parseIpv4(parts[0]);
    final prefix = int.tryParse(parts[1]);
    if (base == null || prefix == null || prefix < 0 || prefix > 32) {
      return null;
    }
    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return (network: base & mask, prefix: prefix);
  }

  static bool _ipInCidr(int ip, String cidr) {
    final parsed = _parseCidr(cidr);
    if (parsed == null) return false;
    final mask =
        parsed.prefix == 0 ? 0 : (0xFFFFFFFF << (32 - parsed.prefix)) & 0xFFFFFFFF;
    return (ip & mask) == parsed.network;
  }
}

class ScopeVerdict {
  const ScopeVerdict.allowed()
      : isAllowed = true,
        reason = null;
  const ScopeVerdict.denied(String this.reason) : isAllowed = false;

  final bool isAllowed;
  final String? reason;
}
