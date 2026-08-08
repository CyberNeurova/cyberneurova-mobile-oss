import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/core/agent/device/linux/paired_devices.dart';

/// Every device this app has paired with, and a way to drop one.
///
/// A pairing grants a shell that can install and remove apps. That is a real
/// grant, and the honest thing is to let someone see what they have handed out
/// and take it back — the key on disk survives reboots and the
/// wireless-debugging toggle, so without this list the only evidence of a
/// pairing is that things mysteriously keep working.
class PairedHistory extends StatelessWidget {
  const PairedHistory({
    super.key,
    required this.devices,
    required this.onForget,
  });

  final List<PairedDevice> devices;
  final void Function(String id) onForget;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAIRED BEFORE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final d in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.smartphone_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5, color: cs.onSurface),
                        ),
                        Text(
                          // First paired, not last used: reviewing a grant is
                          // about recognising when you made it.
                          'paired ${_when(d.firstPairedAt)}'
                          '${d.uid == null ? '' : ' · uid ${d.uid}'}',
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => onForget(d.id),
                    child: const Text('Forget'),
                  ),
                ],
              ),
            ),
          Text(
            // Said plainly. "Forget" removing only our note, while Android
            // keeps the key, is exactly the kind of half-revocation people
            // assume is a full one.
            'Forget removes it from this list. To revoke the access itself, '
            'turn off wireless debugging in Developer options.',
            style:
                TextStyle(fontSize: 11, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    final days = DateTime.now().difference(t).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    if (days < 365) return '${(days / 30).floor()} months ago';
    return '${(days / 365).floor()} years ago';
  }
}
