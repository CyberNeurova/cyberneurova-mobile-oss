import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/mdns.dart';

/// Names the things on the network, instead of guessing from open ports.
///
/// `net_scan` answers "192.168.1.31 has 8009 open". This answers "that is
/// Living Room TV and it speaks `_googlecast._tcp`". For an agent choosing what
/// to do next the difference is between a fact and an inference — and it is
/// obtainable only from the phone, because mDNS never crosses the user's own
/// network segment.
class MdnsDiscoverTool implements DeviceTool {
  const MdnsDiscoverTool();

  @override
  String get name => 'mdns_discover';

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.mdnsDiscovery};

  /// Listens rather than sends: there is no target to check against scope.
  /// What it hears is limited to the segment the phone is already on, which is
  /// the same boundary the scope check exists to enforce.
  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final seconds = (args['seconds'] as int?) ?? 5;
    // Bounded: browsing holds a multicast lock, and an agent that asks for a
    // five-minute browse would keep the radio awake for no extra answers —
    // almost everything responds in the first couple of seconds.
    final timeout = Duration(seconds: seconds.clamp(2, 20));

    context.onProgress('Listening for services for ${timeout.inSeconds}s…');
    final found = await Mdns.discover(timeout: timeout);

    if (context.isCancelled()) {
      return const DeviceToolResult.failure('Cancelled.');
    }
    if (found.isEmpty) {
      return const DeviceToolResult(
        ok: true,
        summary: 'Nothing announced itself',
        // An empty result is a finding, not a failure — plenty of networks
        // have mDNS blocked, and saying so stops the agent retrying.
        output: 'No mDNS services responded. The network may block multicast, '
            'or there may genuinely be nothing announcing itself.',
      );
    }

    return DeviceToolResult(
      ok: true,
      summary: '${found.length} service${found.length == 1 ? '' : 's'} '
          'on this network',
      output: [for (final s in found) s.line].join('\n'),
    );
  }
}
