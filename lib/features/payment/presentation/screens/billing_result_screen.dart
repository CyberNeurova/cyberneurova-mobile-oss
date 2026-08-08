import 'package:cyberneurova_mobile/features/payment/presentation/screens/billing_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Outcome screen shown after the webview closes / the poll terminates.
/// Status is "paid" | "expired" | "failed".
class BillingResultScreen extends ConsumerWidget {
  const BillingResultScreen({super.key, required this.status});
  final String status;

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed' || status == 'expired';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(authProvider).valueOrNull;
    final tier = user?.tier ?? 'free';

    final icon = isPaid
        ? Icons.check_circle_rounded
        : Icons.error_outline_rounded;
    final color = isPaid ? cs.primary : cs.error;
    final title = isPaid
        ? 'You\'re on ${_tierLabel(tier)}'
        : status == 'expired'
            ? 'Invoice expired'
            : 'Payment failed';
    final body = isPaid
        ? 'Thanks for upgrading. Premium features are unlocked across the app.'
        : "Don't worry — nothing was charged. Try again or pick a different payment method.";

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                ),
                child: Icon(icon, size: 52, color: color),
              )
                  .animate()
                  .scaleXY(
                    begin: 0.4,
                    end: 1.0,
                    duration: 360.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 240.ms),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                // serifDisplay defaults to the dark palette's near-white;
                // pass the live scheme's ink so light mode reads.
                style: AppTheme.serifDisplay(size: 28, color: cs.onSurface),
              ).animate().fadeIn(delay: 200.ms, duration: 240.ms),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 15,
                  height: 1.5,
                ),
              ).animate().fadeIn(delay: 280.ms, duration: 240.ms),
              const Spacer(),

              if (isPaid)
                FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    // Go all the way back to chats
                    context.goNamed('chats');
                  },
                  child: const Text('Start using Premium'),
                )
              else ...[
                FilledButton(
                  onPressed: () => context.pushReplacementNamed('billing-plans'),
                  child: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.goNamed('chats'),
                  child: const Text('Maybe later'),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Was its own switch ending in `_ => 'Free'` — the same trap billing history
  // had, on the screen shown the moment a purchase completes. Someone who had
  // just bought Starter was told their plan was Free. Shared helper now, so
  // there is one place to add a tier.
  String _tierLabel(String t) => tierLabel(t);
}
