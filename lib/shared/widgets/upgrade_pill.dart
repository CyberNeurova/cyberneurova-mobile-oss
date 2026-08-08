import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Compact "Upgrade" pill shown next to free-tier identity/billing rows
/// (drawer header, settings Billing row). Quietly branded: primary @ .12
/// fill + primary-ink label, [AppTheme.radiusXl] pill shape, ≥32px tall so
/// it stays a comfortable target inside a 44px row.
///
/// Callers are responsible for gating on tier + PlatformFlags.showUpgradeCta
/// and for navigation (the drawer must capture its router before popping;
/// settings can use its own context) — hence the plain [onTap].
class UpgradePill extends StatelessWidget {
  const UpgradePill({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Whether [tier] renders as the free plan. Mirrors the `_tierLabel`
  /// switches in app_drawer/settings_screen: anything that isn't a known
  /// paid tier falls through to the free-plan label, so it gets the pill.
  static bool isFreeTier(String? tier) => switch (tier) {
        'pro' || 'pro_max' || 'premium' => false,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Light-mode legibility: same ink-blend as the drawer header — the
    // light palette's primary is only ~2.9:1 as small text, so deepen it
    // with onSurface ink to clear 4.5:1. Dark keeps the brand teal.
    final accentInk = Theme.of(context).brightness == Brightness.light
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.35), cs.primary)
        : cs.primary;

    return Material(
      color: cs.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            AppL10n.of(context).upgrade,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentInk,
            ),
          ),
        ),
      ),
    );
  }
}
