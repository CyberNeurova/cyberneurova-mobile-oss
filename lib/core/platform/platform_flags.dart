import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Cross-platform feature flags. Centralised so the rules are visible and
/// auditable in one place — not scattered as `if (Platform.isIOS)` calls
/// across the app.
class PlatformFlags {
  PlatformFlags._();

  // ─── Platform detection ───────────────────────────────────────────────────
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMobile => isIOS || isAndroid;

  // ─── App Store / Play Store rule: payment surfaces ────────────────────────

  /// Whether to render any "buy / upgrade / subscribe" UI in the app.
  ///
  /// **All platforms: true (as of build 32, 2026-07-02).** Restored per
  /// user decision; the previous `!isIOS` gate (added after Apple's 2.1(b)
  /// rejection on build 29) shipped a free-tier-only iOS build. The user
  /// has explicitly accepted the review risk of showing paywall/plans UI
  /// on iOS without StoreKit IAP. If Apple rejects again under 3.1.1 or
  /// 2.1(b), the reversal path is to flip this back to `!isIOS` and either
  /// wait for the desktop-team-owned payment layer (outbox/034) or apply
  /// for Apple's External Link Account Entitlement + add the required
  /// disclosure sheet. See git history for the previous gating impl.
  static bool get showBilling => true;

  /// Whether to show an "Upgrade" CTA on locked features (model picker,
  /// quota exceeded errors, tier badge). Mirrors [showBilling] but kept
  /// separate so we can A/B-test if Apple's policy changes.
  static bool get showUpgradeCta => showBilling;

  // ─── Device capabilities ──────────────────────────────────────────────────

  /// Whether this platform can give the agent a real shell on the device.
  ///
  /// Android only, and not by our choice: the Console and Code surfaces run a
  /// PTY inside a PRoot'd Linux rootfs ([ProotRuntime], [PtyShell]), which
  /// needs the ability to execute a binary the app itself unpacked. iOS does
  /// not permit that to any app, so there is no version of this that ships
  /// later — it is a platform boundary, not a backlog item.
  ///
  /// Centralised here for the reason this file exists. The eight
  /// `Platform.isAndroid` checks scattered through `core/agent/device` each
  /// stop one machine-level operation, which is correct but invisible from the
  /// UI: they made every device feature fail politely one layer below a screen
  /// that had already promised it. This flag is what the UI asks BEFORE
  /// offering the feature at all.
  static bool get hasDeviceShell => isAndroid;
}
