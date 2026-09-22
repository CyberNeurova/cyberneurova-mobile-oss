import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/remote/data/models/remote_device.dart';
import 'package:cyberneurova_mobile/features/remote/data/repositories/remote_control_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';

/// Attaches to a device by opening its relay page in a webview, after minting a
/// session and injecting the session cookie into the webview's own jar.
///
/// Flow (chat spec `mobile/chat/2026-08-29-0840`): `POST /remote/session`
/// (Bearer) → read the `cnrc_session` cookie from the BODY → inject it for the
/// relay host → load `attach_url`. The in-page socket rides the same cookie;
/// nothing changes on the host protocol.
class RemoteAttachScreen extends ConsumerStatefulWidget {
  const RemoteAttachScreen({super.key, required this.device});

  final RemoteDevice device;

  @override
  ConsumerState<RemoteAttachScreen> createState() => _RemoteAttachScreenState();
}

class _RemoteAttachScreenState extends ConsumerState<RemoteAttachScreen> {
  WebViewController? _webview;
  Object? _error;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _webview = null;
    });
    try {
      final attach = widget.device.attachUrl;
      final uri = attach == null ? null : Uri.tryParse(attach);
      if (uri == null || uri.scheme != 'https') {
        throw const ApiException('This device has no secure attach URL.');
      }

      // 1) Mint the relay session. The cookie value comes back in the BODY (a
      //    Flutter webview has its own cookie jar, so Set-Cookie won't reach it).
      final cookie = await ref
          .read(remoteControlRepositoryProvider)
          .createSession(widget.device.deviceId);
      if (cookie == null) {
        throw const ApiException('Could not open a session for this device.');
      }
      if (!mounted) return;

      // 2) Inject the session cookie for the relay host BEFORE loading.
      //    NOTE (pending chat's confirm — my reply `mobile/chat/…-1035`):
      //    webview_flutter's WebViewCookie can't set `httpOnly`. A non-httpOnly
      //    cookie is still sent on same-origin requests, so the in-page socket
      //    carries it; if the relay strictly REQUIRES httpOnly we swap to the
      //    `webview_cookie_manager` package.
      await WebViewCookieManager().setCookie(WebViewCookie(
        name: 'cnrc_session',
        value: cookie,
        domain: uri.host,
        path: '/',
      ));

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Theme.of(context).colorScheme.surface)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
        ))
        ..loadRequest(uri);
      if (!mounted) return;
      setState(() => _webview = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.label ?? 'Remote'),
        bottom: _progress > 0 && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 2,
                  color: cs.primary,
                  backgroundColor: cs.outline,
                ),
              )
            : null,
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _connect)
          : _webview == null
              ? Center(child: CircularProgressIndicator(color: cs.primary))
              : WebViewWidget(controller: _webview!),
    );
  }
}
