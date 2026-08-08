import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cyberneurova_mobile/core/analytics/analytics_repository.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/providers/iap_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';

/// Why the paywall fired. Used to swap the headline + highlighted
/// benefit row to make the upgrade prompt feel contextual instead of
/// generic. Server returns specific error codes (TIER_REQUIRED,
/// SIZE_LIMIT_FREE, INSUFFICIENT_UNITS, MODEL_ACCESS_DENIED, …);
/// callers map those to one of these reasons and pass it in.
enum PaywallReason {
  fileUpload, // 403 TIER_REQUIRED on /files/upload (post-Vercel)
  fileSizeLimit, // 413 SIZE_LIMIT_FREE on /files/upload
  premiumModel, // 403 MODEL_ACCESS_DENIED in chat completion or model picker
  insufficientUnits, // 403 INSUFFICIENT_UNITS in chat completion
  imageGenCap, // 403 image gen daily cap
  webSearchRateLimit, // 429 RATE_LIMITED on web search
  voiceListen, // 403 TIER_REQUIRED on /tts (per-message Listen button)
  voiceSpeak, // 403 TIER_REQUIRED on /voice/transcribe (mic button)
  generic, // user tapped a Pro badge / settings entry to learn more
}

/// Payload carried in [pendingPaywallTriggerProvider]. Notifiers (e.g.
/// the upload flow on TIER_REQUIRED) write this; the chat detail screen
/// listens and surfaces the paywall sheet.
class PaywallTrigger {
  const PaywallTrigger({required this.reason, this.details});
  final PaywallReason reason;
  final Map<String, dynamic>? details;
}

/// Set by notifiers to request the paywall sheet, read by screens.
/// Cleared (set to null) immediately after the screen consumes it so
/// repeated triggers all surface.
final pendingPaywallTriggerProvider =
    StateProvider<PaywallTrigger?>((_) => null);

/// Contextualized upgrade nudge — a lightweight bottom sheet, not a store.
///
/// One flow everywhere: this sheet's single CTA pushes the Plans screen
/// ('billing-plans'), which owns pricing, the store purchase flow (IAP when
/// available) and the web-checkout fallback. Returns true when the user
/// tapped through to Plans.
///
/// Apple requires a visible "Restore Purchases" wherever a paywall shows
/// (the backend API §6) — rendered here whenever the store is available on this
/// platform.
Future<bool> showPaywall(
  BuildContext context, {
  required PaywallReason reason,
  Map<String, dynamic>? details,
}) async {
  // Guarded by PlatformFlags.showBilling — currently `true` on every
  // platform. If a future rollback re-hides on iOS, callers already treat
  // false as "user declined" so no other change is needed.
  if (!PlatformFlags.showBilling) return false;
  HapticFeedback.mediumImpact();
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        ),
        builder: (_) => _PaywallSheet(reason: reason, details: details),
      ) ??
      false;
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet({required this.reason, this.details});
  final PaywallReason reason;
  final Map<String, dynamic>? details;

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget analytics — paywall impressions help us tune which
    // reasons actually convert vs which are pure friction.
    Future.microtask(() {
      ref.read(analyticsRepositoryProvider).track(
        eventType: 'paywall_shown',
        category: 'billing',
        metadata: {
          'reason': widget.reason.name,
          if (widget.details != null) ...widget.details!,
        },
      );
    });
  }

  ({String headline, String highlight}) _copy(PaywallReason r) {
    return switch (r) {
      PaywallReason.fileUpload => (
          headline: 'Upload files with Pro',
          highlight: 'Attach images and documents to every chat',
        ),
      PaywallReason.fileSizeLimit => (
          headline: 'Bigger uploads with Pro',
          highlight: 'Up to 10 MB per file (2 MB on Free)',
        ),
      PaywallReason.premiumModel => (
          headline: 'Unlock the flagship model',
          highlight: 'Cyberneurova-Qwen and every premium model',
        ),
      PaywallReason.insufficientUnits => (
          headline: 'You\'re out of units',
          highlight: 'Pro gives 1.4B units / week — never run out',
        ),
      PaywallReason.imageGenCap => (
          headline: 'More images with Pro',
          highlight: 'Up to 50 generated images per day',
        ),
      PaywallReason.webSearchRateLimit => (
          headline: 'Higher search limits with Pro',
          highlight: 'Faster, more frequent web searches',
        ),
      PaywallReason.voiceListen => (
          headline: 'Listen to answers with Pro',
          highlight: 'Hear any assistant response read aloud',
        ),
      PaywallReason.voiceSpeak => (
          headline: 'Speak to chat with Pro',
          highlight: 'Voice messages auto-transcribed and sent',
        ),
      PaywallReason.generic => (
          headline: 'Unlock more with Pro',
          highlight: 'Everything CyberNeurova can do, no limits',
        ),
    };
  }

  void _seePlans() {
    HapticFeedback.lightImpact();
    ref.read(analyticsRepositoryProvider).track(
      eventType: 'paywall_converted',
      category: 'billing',
      metadata: {'reason': widget.reason.name},
    );
    // Capture the router before popping — the sheet's context dies with it.
    final router = GoRouter.of(context);
    Navigator.pop(context, true);
    router.pushNamed('billing-plans');
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      await ref.read(iapPurchaseControllerProvider.notifier).restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking the store for your purchases…'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t reach the store. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final copy = _copy(widget.reason);
    // Store availability decides whether "Restore purchases" renders —
    // Apple requires it wherever a paywall shows (§6); on platforms where
    // the store is unavailable it would only dead-end.
    final storeAvailable =
        ref.watch(iapAvailabilityProvider).valueOrNull?.available ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Headline
            Text(
              copy.headline,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),

            // Reason-specific benefit row — the one thing the user was just
            // blocked on, in a soft primary-tinted card.
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: cs.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      copy.highlight,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // A short taste of the rest — the full list lives on Plans.
            _Benefit(cs: cs, text: '1.4 billion units per week'),
            _Benefit(cs: cs, text: 'All models including the flagship'),
            _Benefit(cs: cs, text: 'Voice, bigger uploads, more images'),

            const SizedBox(height: 20),

            // One flow: nudge → Plans screen (pricing + purchase live there).
            CnButton(label: 'See plans', onPressed: _seePlans),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44)),
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Not now',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            if (storeAvailable)
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44)),
                  onPressed: _restoring ? null : _restore,
                  child: Text(
                    'Restore purchases',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            // Apple 3.1.2(c): renewal disclosure + Terms/Privacy links on
            // every surface that leads into a subscription purchase.
            const SizedBox(height: 6),
            _PaywallLegalFooter(cs: cs),
          ],
        ),
      ),
    );
  }
}

class _PaywallLegalFooter extends StatelessWidget {
  const _PaywallLegalFooter({required this.cs});
  final ColorScheme cs;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(
      fontSize: 11,
      color: cs.onSurfaceVariant,
      height: 1.4,
    );
    final linkStyle = TextStyle(
      fontSize: 11,
      color: cs.primary,
      height: 1.4,
      decoration: TextDecoration.underline,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Subscriptions auto-renew monthly until cancelled at least 24 '
          'hours before the end of the current period. Payment is charged '
          'to your Apple ID at confirmation of purchase.',
          textAlign: TextAlign.center,
          style: bodyStyle,
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _open(AppConstants.termsUrl),
              child: Text('Terms of Use (EULA)', style: linkStyle),
            ),
            Text('  ·  ', style: bodyStyle),
            GestureDetector(
              onTap: () => _open(AppConstants.privacyPolicyUrl),
              child: Text('Privacy Policy', style: linkStyle),
            ),
          ],
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.cs, required this.text});
  final ColorScheme cs;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
