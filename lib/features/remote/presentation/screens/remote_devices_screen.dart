import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/remote/data/models/remote_device.dart';
import 'package:cyberneurova_mobile/features/remote/presentation/providers/remote_providers.dart';

/// Remote Control — the list of your online devices to attach to and drive
/// (mobile = controller). Tapping one opens its relay page in an attach
/// webview. The relay isn't live yet, so this normally shows the empty state.
class RemoteDevicesScreen extends ConsumerWidget {
  const RemoteDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(remoteDevicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote control'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.invalidate(remoteDevicesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(remoteDevicesProvider),
        child: devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Empty(
            icon: Icons.wifi_tethering_off_rounded,
            title: 'No devices available',
            body: userMessageFor(context, e),
          ),
          data: (list) => list.isEmpty
              ? const _Empty(
                  icon: Icons.devices_other_rounded,
                  title: 'No devices online',
                  body: 'Open Code on your desktop (or the CLI) and it will '
                      'appear here to attach to and drive from your phone.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _DeviceTile(device: list[i]),
                ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final RemoteDevice device;

  IconData get _icon => switch (device.kind) {
        'desktop' => Icons.desktop_windows_rounded,
        'cli' => Icons.terminal_rounded,
        _ => Icons.devices_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      enabled: device.canAttach,
      leading: CircleAvatar(
        backgroundColor: cs.primary.withValues(alpha: 0.16),
        child: Icon(_icon, color: cs.primary),
      ),
      title: Text(device.label ?? device.kind,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: Color(0xFF2FBF71), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('Online', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      onTap: device.canAttach
          ? () => context.pushNamed('remote-attach', extra: device)
          : null,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A ListView so RefreshIndicator can still be pulled when empty.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        Icon(icon, size: 44, color: cs.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 8),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5, height: 1.45, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
