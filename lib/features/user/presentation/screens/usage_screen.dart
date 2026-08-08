import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/user/data/models/usage_model.dart';
import 'package:cyberneurova_mobile/features/user/presentation/providers/usage_provider.dart';

/// Minimal Usage screen. Shows token consumption, plan, reset date.
/// Replaces the old TODO-route that pushed the user into Edit Profile.
class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final lastTurn = ref.watch(lastTurnUsageProvider);
    final tokens = user?.tokens;
    final usageAsync = ref.watch(usageDetailProvider);

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Usage'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Detailed breakdown card — shown only for v2 (non-legacy)
          // accounts. v1 falls through to the legacy tokens card below.
          usageAsync.maybeWhen(
            data: (u) =>
                u.legacy ? const SizedBox.shrink() : _DetailedUsageCard(u),
            orElse: () => const SizedBox.shrink(),
          ),
          usageAsync.maybeWhen(
            data: (u) => u.legacy
                ? const SizedBox.shrink()
                : const SizedBox(height: 12),
            orElse: () => const SizedBox.shrink(),
          ),

          // Tokens card — LEGACY accounts only.
          //
          // This used to render for everyone, so a v2 account saw the live
          // breakdown above (Weekly 2.4M / 1400M) and then a "Tokens 0 / 60.0M"
          // card underneath, reading a counter that is not the one being
          // filled. The comment on the card above already said v1 "falls
          // through to the legacy tokens card below"; it just was not
          // enforced. Seen on the owner's Pro account after a day of use.
          if (usageAsync.valueOrNull?.legacy ?? true)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.toll_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Tokens',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (tokens != null)
                      Text(
                        '${_fmt(tokens.used)} / ${_fmt(tokens.limit)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (tokens != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: tokens.limit > 0
                          ? (tokens.used / tokens.limit).clamp(0.0, 1.0)
                          : 0.0,
                      minHeight: 6,
                      backgroundColor: cs.outline,
                      valueColor: AlwaysStoppedAnimation(
                        tokens.limit > 0 && tokens.used / tokens.limit >= 0.9
                            ? cs.error
                            : cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_fmt(tokens.remaining)} remaining',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  if (tokens.resetAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Resets ${_when(tokens.resetAt!)}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ] else ...[
                  Text(
                    'No usage data yet. Send a message to populate.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Plan card
          _Card(
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Plan',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  _planLabel(user?.tier),
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (PlatformFlags.showBilling) ...[
            const SizedBox(height: 12),
            // Upgrade CTA (Android/web — iOS hides per App Store rules)
            FilledButton.icon(
              onPressed: () => context.pushNamed('billing-plans'),
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              label: const Text('See plans'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],

          if (lastTurn != null) ...[
            const SizedBox(height: 24),
            Text(
              'Last message',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetaRow(
                    label: 'Input tokens',
                    value: _fmt(lastTurn.inputTokens),
                  ),
                  const SizedBox(height: 6),
                  _MetaRow(
                    label: 'Output tokens',
                    value: _fmt(lastTurn.outputTokens),
                  ),
                  const SizedBox(height: 6),
                  _MetaRow(
                    label: 'Total',
                    value: _fmt(lastTurn.totalTokens),
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _when(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) return 'soon';
    if (diff.inDays >= 1) return 'in ${diff.inDays}d';
    if (diff.inHours >= 1) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }

  String _planLabel(String? tier) => switch (tier) {
        'pro_max' => 'Max',
        'pro' => 'Pro',
        'premium' => 'Premium',
        _ => 'Free',
      };
}

/// Detailed v2 breakdown: session window + weekly bucket + premium weekly
/// bucket. Each row is a thin label + meter. Renders only when the
/// /user/usage endpoint returns non-legacy data.
class _DetailedUsageCard extends StatelessWidget {
  const _DetailedUsageCard(this.usage);
  final UsageDetail usage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text('Breakdown',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                usage.billingCycle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          if (usage.session != null) ...[
            const SizedBox(height: 16),
            _MeterRow(
                label: 'Session', bucket: usage.session!, hideLimit: true),
          ],
          if (usage.weekly != null) ...[
            const SizedBox(height: 14),
            _MeterRow(label: 'Weekly', bucket: usage.weekly!),
          ],
          if (usage.weeklyPremium != null) ...[
            const SizedBox(height: 14),
            _MeterRow(
                label: 'Weekly premium', bucket: usage.weeklyPremium!),
          ],
          if (usage.extraUnits != null && usage.extraUnits!.remaining > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.bolt_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  '${usage.extraUnits!.remaining.toString()} extra units remaining',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.label,
    required this.bucket,
    this.hideLimit = false,
  });
  final String label;
  final UsageBucket bucket;
  final bool hideLimit;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = bucket.limit > 0 ? (bucket.used / bucket.limit).clamp(0.0, 1.0) : 0.0;
    final progressColor = pct >= 0.9
        ? cs.error
        : pct >= 0.75
            ? const Color(0xFFFFB347)
            : cs.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
            const Spacer(),
            Text(
              hideLimit || bucket.limit == 0
                  ? _fmt(bucket.used)
                  : '${_fmt(bucket.used)} / ${_fmt(bucket.limit)}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        if (bucket.limit > 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: cs.outline,
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: child,
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
