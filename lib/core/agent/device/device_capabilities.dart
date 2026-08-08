import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';

/// What a device can physically do.
///
/// Names match `docs/shell/06-AGENT-INTEGRATION.md` §2.1 so the block this
/// generates lines up with what the server-side prompt expects.
enum DeviceCapability {
  /// Reach hosts on the LAN the phone is attached to. The one thing a
  /// container can never do.
  localNetwork,

  /// Unprivileged TCP connect. Available in pure Dart on both platforms.
  tcpConnect,

  /// Outbound HTTP/HTTPS.
  httpClient,

  /// DNS resolution, including DoH.
  dnsResolve,

  /// Read/write inside the app's own container.
  fileSandbox,

  /// `SOCK_DGRAM` + `IPPROTO_ICMP`. Unprivileged on Darwin, but needs a
  /// platform channel — not reachable from pure Dart.
  icmpDgram,

  /// mDNS / Bonjour / SSDP enumeration. Needs `NWBrowser` (iOS) or multicast
  /// sockets (Android) via a platform channel.
  mdnsDiscovery,

  /// Raw sockets — SYN/FIN scans, OS fingerprinting, ARP. Never on iOS
  /// (kernel-enforced), Android only with root.
  rawSocket,

  /// Packet capture via `NEPacketTunnelProvider` / `VpnService`.
  packetCapture,

  /// Execute downloaded binaries. Never on iOS — AMFI code signing is
  /// enforced in the kernel and is not waivable per-app.
  execBinary,

  /// Bind ports below 1024.
  privilegedPorts,

  /// Install an APK on this device.
  ///
  /// Android only, and available WITHOUT root or ADB: PackageInstaller shows
  /// the user a system confirmation, which is the universal path every phone
  /// has. A privileged channel only makes it silent, not possible.
  installPackages,
}

extension DeviceCapabilityName on DeviceCapability {
  String get wireName => switch (this) {
        DeviceCapability.localNetwork => 'LOCAL_NETWORK',
        DeviceCapability.tcpConnect => 'TCP_CONNECT',
        DeviceCapability.httpClient => 'HTTP_CLIENT',
        DeviceCapability.dnsResolve => 'DNS_RESOLVE',
        DeviceCapability.fileSandbox => 'FILE_SANDBOX',
        DeviceCapability.icmpDgram => 'ICMP_DGRAM',
        DeviceCapability.mdnsDiscovery => 'MDNS_DISCOVERY',
        DeviceCapability.rawSocket => 'RAW_SOCKET',
        DeviceCapability.packetCapture => 'PACKET_CAPTURE',
        DeviceCapability.execBinary => 'EXEC_BINARY',
        DeviceCapability.privilegedPorts => 'PRIVILEGED_PORTS',
        DeviceCapability.installPackages => 'INSTALL_PACKAGES',
      };
}

/// The capability set for one device, plus the prompt block derived from it.
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.platform,
    required this.osVersion,
    required this.present,
    this.installedToolsets = const [],
    this.availableCommands = const [],
    this.canInstallTools = false,
  });

  /// `ios` | `android`.
  final String platform;
  final String osVersion;
  final Set<DeviceCapability> present;
  final List<String> installedToolsets;

  /// Commands actually resolvable on `$PATH` right now.
  ///
  /// From `PrefixBootstrap`, which asks the filesystem rather than trusting a
  /// map — so this is what the shell will really find, not what we intended
  /// to ship. Once tools arrive at runtime (`13-RUNTIME-INSTALL.md`) the set
  /// is different per user and per session, which is exactly why it has to be
  /// computed per turn instead of hardcoded.
  final List<String> availableCommands;

  /// Whether more tools can be obtained on this device at all.
  ///
  /// False is the honest answer today on iOS (AMFI, permanently) and on any
  /// build with no delivery route wired. Telling the agent it can install
  /// when it can't produces the worst loop of all: it "fixes" a missing tool
  /// by installing it, the install silently no-ops, and it tries again.
  final bool canInstallTools;

  bool has(DeviceCapability c) => present.contains(c);

  Set<DeviceCapability> get missing =>
      DeviceCapability.values.toSet().difference(present);

  /// What a stock Flutter build can actually do today, with no platform
  /// channels and no Rust core: TCP connect, HTTP, DNS, and the app sandbox.
  ///
  /// Everything else — ICMP, mDNS, capture — is deliberately absent rather
  /// than optimistically claimed. Claiming a capability the device lacks is
  /// worse than lacking it: the model proposes the technique, the call fails,
  /// and it retries the same thing.
  static Set<DeviceCapability> get pureDartBaseline => {
        DeviceCapability.localNetwork,
        DeviceCapability.tcpConnect,
        DeviceCapability.httpClient,
        DeviceCapability.dnsResolve,
        DeviceCapability.fileSandbox,
      };

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'os_version': osVersion,
        'capabilities': [for (final c in present) c.wireName],
        'missing': [for (final c in missing) c.wireName],
        'installed_toolsets': installedToolsets,
        'available_commands': availableCommands,
        'can_install_tools': canInstallTools,
      };

  /// The block injected into the system prompt each turn.
  ///
  /// `06-AGENT-INTEGRATION.md` §2.1 is emphatic about this, and it is right:
  /// *"Without this the model will propose `nmap -sS` on an unrooted device
  /// and loop on the failure. With it, it proposes a connect scan and
  /// mentions the trade-off. This single block removes most agentic failure
  /// in this domain."*
  ///
  /// Generated from the live capability set, never hand-written, so it cannot
  /// drift from what the executor will actually accept.
  String promptBlock({
    required AuthorizedScope scope,
    String? cwd,
    List<String> localSubnetCidrs = const [],
    List<String> selfIps = const [],
    bool underProot = false,
  }) {
    final buf = StringBuffer()
      // Said first, and said plainly, because models do not conclude it on
      // their own. Given a heading and a capability list, GLM 5.2 opened a
      // real session with "You are currently operating within a simulated
      // environment" and then described the user's actual device fingerprint
      // underneath it — measured on an SM-A546E, 2026-08-03.
      //
      // That belief is not cosmetic. A model that thinks it is in a sandbox
      // narrates commands instead of running them, which is exactly the
      // "it said it wrote the code but the shell is empty" report: from the
      // user's side an imagined action and a refused one look the same.
      //
      // Consequences, not adjectives — "real" alone reads as flavour text,
      // whereas "the file is still there tomorrow" is checkable.
      ..writeln(
        'THIS IS REAL HARDWARE. You are running on a physical phone that '
        'belongs to the user, not a sandbox, simulation or example. Every '
        'fact below was measured from it just now. Tool calls have real '
        'effects: a file you write is still there tomorrow, a packet you '
        'send leaves this handset on the user\'s own connection, a package '
        'you install takes up their storage. Never describe a command as '
        'though you had run it — run it, and report what actually happened.',
      )
      ..writeln('EXECUTOR: device ($platform $osVersion)')
      ..writeln('CAPABILITIES: ${[for (final c in present) c.wireName].join(', ')}')
      ..writeln('MISSING: ${[for (final c in missing) c.wireName].join(', ')}');

    if (installedToolsets.isNotEmpty) {
      buf.writeln('INSTALLED TOOLSETS: ${installedToolsets.join(', ')}');
    }

    // The device's own address, stated as a fact so the model can answer
    // "what's my IP" straight from here rather than shelling out — which it did
    // for 14+ failing tool calls before giving up. NOTE: on its own this has
    // NOT proven enough to stop a weak model (Gemma) looping; it still shelled
    // out and even ignored a command that DID return the address. Kept because
    // it is accurate and a capable model can use it, but the flail is a model
    // limitation, not something this line alone fixes.
    if (selfIps.isNotEmpty) {
      final where =
          localSubnetCidrs.isNotEmpty ? ' (on ${localSubnetCidrs.join(', ')})' : '';
      buf.writeln("THIS DEVICE'S IP: ${selfIps.join(', ')}$where — answer any "
          "question about the device's own address from this line; do not run a "
          'shell command to discover it.');
    }

    if (underProot) {
      // The shell is a PRoot Linux guest, not Android's — busybox plus whatever
      // is installed, so Android-toybox assumptions are off. Deliberately does
      // NOT claim network tools fail: an earlier draft asserted `ip`/`ifconfig`/
      // `hostname -I` "return nothing", but on device `ifconfig` DID succeed and
      // print the address — the behaviour is inconsistent, so stating it as a
      // rule was false. Point at the IP line above instead of describing which
      // tools work.
      buf.writeln(
        'SHELL: a PRoot Linux guest (busybox plus whatever you install), not '
        "Android's toybox. For the device's own address, use the IP line above "
        'rather than reading it from the shell.',
      );
    } else if (platform == 'android') {
      // The bare Android shell is never empty even with nothing bundled —
      // toybox is on PATH. Saying so stops the model treating a fresh install
      // as "no tools" and refusing work it can actually do.
      buf.writeln(
        'BASE TOOLS: /system/bin/sh plus the system toybox applets '
        '(ls cat grep sed awk find tar nc ps netstat ping wget vi …)',
      );
    }
    if (availableCommands.isNotEmpty) {
      // Bounded: a busybox link farm is ~350 names and would crowd out the
      // rest of the prompt. The agent can always ask the shell itself.
      const shown = 60;
      final head = availableCommands.take(shown).join(', ');
      final extra = availableCommands.length - shown;
      buf.writeln('EXTRA COMMANDS ON PATH: $head'
          '${extra > 0 ? ' … (+$extra more; run `ls \$PREFIX/bin`)' : ''}');
    }
    buf.writeln(
      canInstallTools
          ? 'INSTALLING TOOLS: available — ask before installing, then '
              'verify with `which <tool>` before relying on it.'
          : 'INSTALLING TOOLS: NOT available on this build. Do not propose '
              '`apt`, `apk`, `pip install` or downloading a binary and running '
              'it — a downloaded binary cannot be executed here. Solve the '
              'task with the tools listed above, or say plainly that it needs '
              'a tool this device does not have.',
    );

    final scopeLine = scope.isEmpty
        ? 'this device only'
        : [
            if (scope.includeLocalSubnet && localSubnetCidrs.isNotEmpty)
              ...localSubnetCidrs
            else if (scope.includeLocalSubnet)
              'local subnet (unresolved)',
            ...scope.cidrs,
            ...scope.hostPatterns,
          ].join(', ');
    buf.writeln('AUTHORIZED SCOPE: $scopeLine');

    if (cwd != null && cwd.isNotEmpty) buf.writeln('CWD: $cwd');
    return buf.toString().trimRight();
  }
}
