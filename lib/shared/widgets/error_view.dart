import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/payment_repository.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';

/// Unified error UI. Auto-picks the right visual + copy based on the
/// exception type — network gets a wifi icon, quota gets an upgrade CTA,
/// rate-limit gets a live countdown, etc.
///
/// Drop this in any `.when(error: (e, _) => ErrorView(error: e, onRetry: …))`.
class ErrorView extends ConsumerWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  /// The thrown error. If it's not an [AppException], it gets wrapped as a
  /// generic [ApiException] with the toString as message.
  final Object error;

  /// Optional retry callback. If null, no retry button is shown.
  final FutureOr<void> Function()? onRetry;

  /// Smaller layout for inline use (list items, cards). Default = full-screen.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final spec = _specForError(context, ref, error, l10n, cs);

    final iconWidget = Icon(spec.icon, size: compact ? 40 : 56,
            color: spec.color.withValues(alpha: 0.7))
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
            begin: 1.0,
            end: 1.06,
            duration: 1800.ms,
            curve: Curves.easeInOut);

    final actionRow = spec.actions.isEmpty
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 8,
            children: spec.actions,
          );

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 32,
        vertical: compact ? 12 : 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          SizedBox(height: compact ? 12 : 16),
          Text(
            spec.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 15 : 17,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          if (spec.body != null) ...[
            SizedBox(height: compact ? 4 : 6),
            Text(
              spec.body!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          if (spec.actions.isNotEmpty) ...[
            SizedBox(height: compact ? 14 : 20),
            actionRow,
          ],
        ],
      ),
    );

    if (compact) return content;
    return Center(child: content);
  }

  _ErrorSpec _specForError(BuildContext context, WidgetRef ref, Object e,
      AppL10n l10n, ColorScheme cs) {
    final retryButton = onRetry == null
        ? null
        : FilledButton.tonalIcon(
            onPressed: () async {
              HapticFeedback.lightImpact();
              await onRetry!();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          );

    switch (e) {
      case NetworkException():
        return _ErrorSpec(
          icon: Icons.wifi_off_rounded,
          color: cs.error,
          title: l10n.errorNetwork,
          body: 'Check your connection and try again.',
          actions: [if (retryButton != null) retryButton],
        );

      case TimeoutException():
        return _ErrorSpec(
          icon: Icons.timer_off_rounded,
          color: cs.error,
          title: e.message,
          body: 'The server is taking longer than usual.',
          actions: [if (retryButton != null) retryButton],
        );

      case UnauthorizedException():
        return _ErrorSpec(
          icon: Icons.lock_outline_rounded,
          color: cs.error,
          title: l10n.errorSessionExpired,
          body: e.message,
          // No retry — router will redirect to login automatically.
          actions: const [],
        );

      case ForbiddenException():
        return _ErrorSpec(
          icon: Icons.block_rounded,
          color: cs.error,
          title: e.message,
          body: e.code == 'EMAIL_NOT_VERIFIED'
              ? 'Check your inbox to confirm your address.'
              : null,
          actions: const [],
        );

      case FeatureUnavailableException():
        return _ErrorSpec(
          icon: Icons.construction_rounded,
          color: cs.primary,
          title: l10n.comingSoon,
          body: 'This feature is rolling out — check back soon.',
          actions: const [],
        );

      case NotFoundException():
        return _ErrorSpec(
          icon: Icons.search_off_rounded,
          color: cs.onSurfaceVariant,
          title: e.message,
          body: null,
          actions: [if (retryButton != null) retryButton],
        );

      case QuotaExceededException():
        return _ErrorSpec(
          icon: Icons.workspace_premium_rounded,
          color: const Color(0xFFFFB347),
          title: l10n.errorQuotaExceeded,
          // iOS shows no upgrade text (App Store rule). Android shows the CTA.
          body: PlatformFlags.showUpgradeCta
              ? 'Upgrade your plan for higher limits.'
              : 'Your daily limit resets soon.',
          actions: [
            if (PlatformFlags.showUpgradeCta)
              FilledButton.icon(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  // Apple 3.1.1: on iOS, upgrades route to the in-app
                  // Plans screen (StoreKit). On other platforms the web
                  // checkout is still valid.
                  if (PlatformFlags.isIOS) {
                    context.pushNamed('billing-plans');
                    return;
                  }
                  final ok = await ref
                      .read(paymentRepositoryProvider)
                      .openUpgrade();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.couldNotOpenBrowser),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.arrow_upward_rounded),
                label: Text(l10n.upgrade),
              ),
            if (retryButton != null) retryButton,
          ],
        );

      case RateLimitedException(:final retryAfterSeconds):
        return _ErrorSpec(
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFFFFB347),
          title: e.message,
          body: retryAfterSeconds == null
              ? null
              : 'Try again in $retryAfterSeconds seconds.',
          actions: [
            if (retryButton != null) retryButton,
          ],
        );

      case ServiceUnavailableException():
        return _ErrorSpec(
          icon: Icons.cloud_off_rounded,
          color: cs.onSurfaceVariant,
          title: e.message,
          body: "We'll be back in a moment.",
          actions: [if (retryButton != null) retryButton],
        );

      case ServerException():
        return _ErrorSpec(
          icon: Icons.cloud_off_rounded,
          color: cs.error,
          title: e.message,
          body: null,
          actions: [if (retryButton != null) retryButton],
        );

      case ApiException(:final statusCode):
        return _ErrorSpec(
          icon: Icons.error_outline_rounded,
          color: cs.error,
          title: e.message,
          body: statusCode != null ? 'Code $statusCode' : null,
          actions: [if (retryButton != null) retryButton],
        );

      default:
        // Last-resort generic — non-AppException thrown somewhere.
        return _ErrorSpec(
          icon: Icons.error_outline_rounded,
          color: cs.error,
          title: l10n.errorGeneric,
          body: e.toString(),
          actions: [if (retryButton != null) retryButton],
        );
    }
  }
}

class _ErrorSpec {
  const _ErrorSpec({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.actions,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final List<Widget> actions;
}
