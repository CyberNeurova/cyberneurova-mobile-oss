import 'dart:async';
import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';

/// TCP connect scan.
///
/// Pure Dart via `Socket.connect`, so it works on iOS and Android with no
/// platform channel and no entitlement beyond local-network permission.
/// Unprivileged, which is the only option on iOS anyway — SYN scans need raw
/// sockets and AMFI makes those impossible there regardless of root.
///
/// This is the archetype for the whole device-executor idea: the scan runs on
/// the phone, against the phone's own LAN, and the server never sees a packet.
class NetScanTool implements DeviceTool {
  @override
  String get name => 'net_scan';

  @override
  Set<DeviceCapability> get requires =>
      {DeviceCapability.tcpConnect, DeviceCapability.localNetwork};

  @override
  String? get targetArgKey => 'target';

  @override
  bool targetIsRange(Map<String, dynamic> args) =>
      (args['target'] as String?)?.contains('/') ?? false;

  /// Conservative default. A full 65535 sweep from a phone is slow, drains
  /// battery, and is exactly the kind of call that should require approval
  /// rather than happening because a model picked a round number.
  static const _topPorts = [
    21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 465, 587, 993, 995,
    1433, 1521, 3000, 3306, 3389, 5000, 5432, 5900, 6379, 8000, 8080,
    8443, 8888, 9000, 9200, 27017,
  ];

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final target = (args['target'] as String).trim();
    final ports = _parsePorts(args['ports']);
    final perPortTimeout = Duration(
      milliseconds: (args['timeout_ms'] as num?)?.toInt() ?? 600,
    );

    if (target.contains('/')) {
      return const DeviceToolResult.failure(
        'Range scanning needs host discovery first. Run net_discover, then '
        'scan the hosts it finds.',
      );
    }

    final open = <int>[];
    var checked = 0;

    // Bounded concurrency: a phone radio handles a handful of parallel
    // connects well and collapses under hundreds.
    const concurrency = 16;
    for (var i = 0; i < ports.length; i += concurrency) {
      if (context.isCancelled()) {
        return DeviceToolResult(
          ok: true,
          summary: 'Cancelled after $checked ports — ${open.length} open',
          output: _format(target, open),
        );
      }
      final batch = ports.skip(i).take(concurrency);
      final results = await Future.wait([
        for (final port in batch) _probe(target, port, perPortTimeout),
      ]);
      for (final r in results) {
        checked++;
        if (r != null) {
          open.add(r);
          context.onProgress('open  $target:$r');
        }
      }
    }

    open.sort();
    return DeviceToolResult(
      ok: true,
      summary: open.isEmpty
          ? 'No open ports found on $target (${ports.length} checked)'
          : '${open.length} of ${ports.length} ports open on $target',
      output: _format(target, open),
    );
  }

  Future<int?> _probe(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return port;
    } catch (_) {
      return null;
    }
  }

  List<int> _parsePorts(Object? raw) {
    if (raw == null || raw == 'top-1000' || raw == 'top') return _topPorts;
    if (raw is List) {
      return [
        for (final p in raw)
          if (p is num) p.toInt() else if (int.tryParse('$p') case final v?) v,
      ];
    }
    final s = raw.toString();
    final out = <int>[];
    for (final part in s.split(',')) {
      final trimmed = part.trim();
      if (trimmed.contains('-')) {
        final bounds = trimmed.split('-');
        final lo = int.tryParse(bounds.first);
        final hi = int.tryParse(bounds.last);
        if (lo != null && hi != null && hi >= lo) {
          // Cap the expansion — a model asking for 1-65535 on a phone gets
          // a useful prefix rather than a twenty-minute scan.
          for (var p = lo; p <= hi && out.length < 1024; p++) {
            out.add(p);
          }
        }
      } else if (int.tryParse(trimmed) case final v?) {
        out.add(v);
      }
    }
    return out.isEmpty ? _topPorts : out;
  }

  String _format(String target, List<int> open) {
    if (open.isEmpty) return 'No open ports on $target.';
    final b = StringBuffer('Open ports on $target:\n');
    for (final p in open) {
      b.writeln('  $p/tcp  ${_serviceHint(p)}');
    }
    return b.toString().trimRight();
  }

  static String _serviceHint(int port) => switch (port) {
        21 => 'ftp',
        22 => 'ssh',
        23 => 'telnet',
        25 => 'smtp',
        53 => 'dns',
        80 => 'http',
        110 => 'pop3',
        143 => 'imap',
        443 => 'https',
        445 => 'smb',
        3306 => 'mysql',
        3389 => 'rdp',
        5432 => 'postgres',
        5900 => 'vnc',
        6379 => 'redis',
        8080 || 8000 || 8888 => 'http-alt',
        8443 => 'https-alt',
        9200 => 'elasticsearch',
        27017 => 'mongodb',
        _ => '',
      };
}

/// Host discovery by TCP probe.
///
/// ICMP sweep would be better and `SOCK_DGRAM` ICMP is unprivileged on
/// Darwin, but it needs a platform channel — so this uses TCP connects to a
/// few common ports instead. Slower and it misses hosts with everything
/// firewalled, which the summary says plainly rather than reporting a clean
/// sweep that isn't.
class NetDiscoverTool implements DeviceTool {
  @override
  String get name => 'net_discover';

  @override
  Set<DeviceCapability> get requires =>
      {DeviceCapability.tcpConnect, DeviceCapability.localNetwork};

  @override
  String? get targetArgKey => 'target';

  @override
  bool targetIsRange(Map<String, dynamic> args) => true;

  /// Ports likely to be open on *something* — a router, a NAS, a printer,
  /// a dev box.
  static const _probePorts = [80, 443, 22, 445, 8080, 631, 5000];

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    var target = (args['target'] as String).trim();

    // "local" resolves at call time from live interface state, which is what
    // makes "scan my network" work without a CIDR — and correctly stop
    // working when the user changes networks.
    if (target == 'local' || target == 'lan') {
      if (context.localSubnetCidrs.isEmpty) {
        return const DeviceToolResult.failure(
          "Couldn't determine this device's subnet. Give an explicit CIDR.",
        );
      }
      target = context.localSubnetCidrs.first;
    }

    final hosts = _expandCidr(target);
    if (hosts == null) {
      return DeviceToolResult.failure(
          '"$target" is not a CIDR this tool can expand (max /24).');
    }

    final live = <String>[];
    var scanned = 0;
    const concurrency = 24;

    for (var i = 0; i < hosts.length; i += concurrency) {
      if (context.isCancelled()) break;
      final batch = hosts.skip(i).take(concurrency);
      final results = await Future.wait([
        for (final h in batch) _isLive(h),
      ]);
      for (var j = 0; j < results.length; j++) {
        scanned++;
        if (results[j] != null) {
          final host = batch.elementAt(j);
          live.add(host);
          context.onProgress('up    $host  (${results[j]}/tcp)');
        }
      }
    }

    return DeviceToolResult(
      ok: true,
      summary: '${live.length} host${live.length == 1 ? '' : 's'} responding '
          'in $target ($scanned probed)',
      output: live.isEmpty
          ? 'No hosts responded on ${_probePorts.join(', ')}. Hosts with all '
              'these ports closed will not appear — this is a TCP probe, not '
              'an ICMP sweep.'
          : 'Live hosts in $target:\n${live.map((h) => '  $h').join('\n')}',
    );
  }

  Future<int?> _isLive(String host) async {
    for (final port in _probePorts) {
      try {
        final s = await Socket.connect(host, port,
            timeout: const Duration(milliseconds: 400));
        s.destroy();
        return port;
      } catch (_) {
        // Try the next port.
      }
    }
    return null;
  }

  /// Expands a CIDR to host addresses. Capped at /24 — a phone sweeping a
  /// /16 over TCP is not a real workflow.
  List<String>? _expandCidr(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 24 || prefix > 32) return null;

    final octets = parts[0].split('.');
    if (octets.length != 4) return null;
    final nums = [for (final o in octets) int.tryParse(o)];
    if (nums.any((n) => n == null || n < 0 || n > 255)) return null;

    final base = (nums[0]! << 24) | (nums[1]! << 16) | (nums[2]! << 8) | nums[3]!;
    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final network = base & mask;
    final count = 1 << (32 - prefix);

    final out = <String>[];
    // Skip network and broadcast addresses on a /24.
    final start = count > 2 ? 1 : 0;
    final end = count > 2 ? count - 1 : count;
    for (var i = start; i < end; i++) {
      final ip = network + i;
      out.add('${(ip >> 24) & 255}.${(ip >> 16) & 255}.'
          '${(ip >> 8) & 255}.${ip & 255}');
    }
    return out;
  }
}

/// DNS lookup. Uses the platform resolver; DoH would need an HTTP client and
/// is better served by `http_probe`.
class DnsQueryTool implements DeviceTool {
  @override
  String get name => 'dns_query';

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.dnsResolve};

  @override
  String? get targetArgKey => 'name';

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final name = (args['name'] as String).trim();
    try {
      final addresses = await InternetAddress.lookup(name);
      if (addresses.isEmpty) {
        return DeviceToolResult(
            ok: true, summary: 'No records for $name', output: '');
      }
      final lines = [
        for (final a in addresses)
          '  ${a.address}  ${a.type == InternetAddressType.IPv6 ? 'AAAA' : 'A'}',
      ];
      return DeviceToolResult(
        ok: true,
        summary: '$name → ${addresses.first.address}'
            '${addresses.length > 1 ? ' (+${addresses.length - 1})' : ''}',
        output: '$name\n${lines.join('\n')}',
      );
    } on SocketException catch (e) {
      return DeviceToolResult.failure(
          "Couldn't resolve $name: ${e.message}");
    }
  }
}
