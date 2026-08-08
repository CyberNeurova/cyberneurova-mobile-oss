import 'package:cyberneurova_mobile/shared/time/record_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/user/presentation/providers/sessions_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.activeSessions),
        actions: [
          // Sahachiel: only offer "sign out all others" when there actually
          // is another session to revoke (otherwise the button is a no-op).
          if (sessions.valueOrNull?.any((s) => !s.isCurrent) ?? false)
            IconButton(
              tooltip: 'Sign out all other devices',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => _confirmRevokeAll(context, ref),
            ),
        ],
      ),
      body: sessions.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: 4,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (_, __) => const ListTile(
            leading: CnShimmer(width: 40, height: 40, radius: 20),
            title: CnShimmer(width: 160, height: 14, radius: 7),
            subtitle: CnShimmer(width: 100, height: 12, radius: 6),
          ),
        ),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.refresh(sessionsProvider.future),
        ),
        data: (list) => list.isEmpty
            ? Center(
                child: Text(
                  'No active sessions',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(sessionsProvider.future),
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) =>
                      _SessionTile(session: list[i]),
                ),
              ),
      ),
    );
  }

  Future<void> _confirmRevokeAll(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sign out all other devices?'),
        content: const Text(
          'This signs out every session except this one. You stay signed in '
          'on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Sign out all',
              style: TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(sessionsProvider.notifier).revokeAllOthers();
    } catch (e) {
      // Sahachiel: surface a clean localized message — a failed bulk revoke
      // on a security screen must not fail silently nor leak a raw exception.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessageFor(context, e))),
        );
      }
    }
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final SessionEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final icon = switch (session.platform.toLowerCase()) {
      'ios' || 'apple' => Icons.phone_iphone_rounded,
      'android' => Icons.phone_android_rounded,
      'web' || 'browser' => Icons.laptop_mac_rounded,
      _ => Icons.devices_other_rounded,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primary.withValues(alpha: 0.15),
        child: Icon(icon, color: cs.primary, size: 20),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              session.deviceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (session.isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'THIS DEVICE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: session.lastUsedAt != null
          ? Text(
              '${session.location ?? ''} • ${_relative(session.lastUsedAt!)}',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant),
            )
          : null,
      trailing: session.isCurrent
          ? null
          : IconButton(
              icon: Icon(Icons.logout_rounded,
                  color: cs.error, size: 20),
              onPressed: () => _confirmRevoke(context, ref),
            ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Revoke session?'),
        content: Text(
          'This will sign out ${session.deviceName} immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Revoke',
              style:
                  TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(sessionsProvider.notifier).revoke(session.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userMessageFor(context, e))),
          );
        }
      }
    }
  }

  String _relative(DateTime dt) => recordTime(dt);
}
