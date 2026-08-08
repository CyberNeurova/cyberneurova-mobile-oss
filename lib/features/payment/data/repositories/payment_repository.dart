import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository();
});

/// All upgrade/billing flows route through an **in-app browser**
/// (SFSafariViewController on iOS, Chrome Custom Tabs on Android)
/// rather than ejecting the user to Safari/Chrome.
///
/// This is the "Starlink pattern" — Apple allows it for digital
/// subscriptions in the post-Epic / DMA era (2024 onward), and it
/// keeps the user feeling "inside" CyberNeurova the whole time:
/// the browser sheet slides up over the app, looks like Safari, but
/// the host app stays alive underneath. Pulling down or tapping Done
/// returns to the chat right where they left off.
///
/// Falls back to external browser if the in-app sheet can't open
/// (e.g. WKWebView disabled by an MDM policy).
class PaymentRepository {
  // Update these if the web app routes change.
  // Verified live 2026-06-28: /pricing → 200; the old /upgrade and
  // /account/billing routes 404. Caught during the App Store pre-flight
  // audit — every Upgrade tap was landing on a broken page.
  static const String _baseUrl = 'https://cyberneurova.ai';
  static const String _upgradeUrl = '$_baseUrl/pricing';
  static const String _billingUrl = '$_baseUrl/pricing';

  /// Opens the upgrade page in the in-app browser sheet.
  /// Returns true on success.
  Future<bool> openUpgrade({String? returnTo}) async {
    final uri = Uri.parse(returnTo == null
        ? _upgradeUrl
        : '$_upgradeUrl?return=${Uri.encodeComponent(returnTo)}');
    return _launchInApp(uri);
  }

  Future<bool> openBilling() => _launchInApp(Uri.parse(_billingUrl));

  Future<bool> _launchInApp(Uri uri) async {
    if (!await canLaunchUrl(uri)) return false;
    try {
      // SFSafariViewController on iOS, Chrome Custom Tabs on Android.
      // User stays "in" CyberNeurova; the page slides up over the app.
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
        browserConfiguration: const BrowserConfiguration(
          showTitle: true,
        ),
      );
      if (ok) return true;
    } catch (_) {
      // Fall through to external — e.g. a WebKit MDM policy blocks
      // in-app browsing.
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
