import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/payment/data/models/billing_models.dart';
import 'package:cyberneurova_mobile/features/payment/data/repositories/billing_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Step 1: create invoice via `BillingRepository.createInvoice`.
/// Step 2: open `invoiceUrl` in a WebView.
/// Step 3: poll `/payment/status` every 3s in the background.
/// Step 4: on `paid` → refresh `/auth/me`, dismiss with success.
/// Step 5: on `expired` / `failed` → show outcome screen with retry.
class CheckoutWebviewScreen extends ConsumerStatefulWidget {
  const CheckoutWebviewScreen({
    super.key,
    required this.tier,
    required this.paymentMethod,
    required this.isYearly,
  });

  final String tier; // premium | pro | pro_max
  final String paymentMethod;
  final bool isYearly;

  @override
  ConsumerState<CheckoutWebviewScreen> createState() =>
      _CheckoutWebviewScreenState();
}

class _CheckoutWebviewScreenState extends ConsumerState<CheckoutWebviewScreen> {
  WebViewController? _webview;
  CreatedInvoice? _invoice;
  InvoiceStatus? _status;
  StreamSubscription<InvoiceStatus>? _pollSub;
  Object? _error;
  double _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final repo = ref.read(billingRepositoryProvider);
      final invoice = await repo.createInvoice(
        tier: widget.tier,
        paymentMethod: widget.paymentMethod,
        isYearly: widget.isYearly,
      );
      if (!mounted) return;
      setState(() => _invoice = invoice);

      // Sahachiel: this is a payment surface, so only ever load a secure (https)
      // checkout URL. Reject anything else before it touches the WebView.
      final invoiceUri = Uri.tryParse(invoice.invoiceUrl);
      if (invoiceUri == null || invoiceUri.scheme != 'https') {
        // AppException so ErrorView shows the clean message (no 'Exception: ').
        throw const ApiException(
            'Could not start a secure checkout. Please try again.');
      }

      // Set up the webview
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Theme.of(context).colorScheme.surface)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) => setState(() => _loadProgress = p / 100),
          onNavigationRequest: _onNavigationRequest,
        ))
        ..loadRequest(invoiceUri);
      setState(() => _webview = controller);

      // Start polling status in the background
      _pollSub = repo.watchInvoice(invoice.invoiceId).listen((s) {
        if (!mounted) return;
        setState(() => _status = s);
        if (s.isPaid) {
          _onPaid();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Sahachiel: payment-WebView navigation hardening. Allow only https inside
  /// the frame; block cleartext http; hand non-web schemes (bank-app / 3DS deep
  /// links, upi://, intent://, mailto:, custom return schemes) to the OS rather
  /// than loading them in the checkout frame. (A tighter per-host allow-list
  /// is deferred: it needs the gateway/3DS domain list + a real device test,
  /// since 3DS legitimately redirects across bank https hosts.)
  Future<NavigationDecision> _onNavigationRequest(
      NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'https') return NavigationDecision.navigate;
    if (uri.scheme == 'http') return NavigationDecision.prevent;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Best-effort hand-off to the OS; a launcher error must never escape the
      // navigation callback (which must always return a NavigationDecision).
    }
    return NavigationDecision.prevent;
  }

  Future<void> _onPaid() async {
    HapticFeedback.heavyImpact();
    _pollSub?.cancel();
    // Refresh auth state so tier badge updates everywhere
    try {
      await ref.read(authProvider.notifier).refreshMe();
    } catch (_) {/* non-fatal */}
    if (mounted) {
      // Replace this route with the result screen
      context.pushReplacementNamed(
        'billing-result',
        queryParameters: {'status': 'paid'},
      );
    }
  }

  @override
  void dispose() {
    _pollSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _confirmExit(context),
        ),
        title: const Text('Checkout'),
        bottom: _loadProgress > 0 && _loadProgress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadProgress,
                  minHeight: 2,
                  color: cs.primary,
                  backgroundColor: cs.outline,
                ),
              )
            : null,
      ),
      body: _error != null
          ? ErrorView(
              error: _error!,
              onRetry: _bootstrap,
            )
          : _invoice == null
              ? Center(
                  child: CircularProgressIndicator(
                      color: cs.primary),
                )
              : Stack(
                  children: [
                    if (_webview != null)
                      WebViewWidget(controller: _webview!),
                    if (_status?.isPending == true)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            border: Border(
                              top: BorderSide(color: cs.outline),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Waiting for payment confirmation…',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Future<void> _confirmExit(BuildContext context) async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel checkout?'),
        content: const Text(
          'Your invoice will stay open — you can complete it later from the Billing screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (exit == true && context.mounted) context.pop();
  }
}
