import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/web_preview.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Runs the web code from a reply.
///
/// The point of the whole feature: on a laptop you save three blocks to a file
/// and open it, and on a phone there is nowhere to save them and nothing to
/// open them with. So the thing the model built runs here, on the device,
/// immediately.
///
/// ## What it deliberately does not do
///
/// No JavaScript channel is registered. The page is model-written code and
/// there is no reason for it to be able to call into the app; without a
/// channel it is an ordinary sandboxed web page and cannot.
///
/// Top-level navigation is refused. Sub-resources still load — a CDN script or
/// a remote image works — but a link that would replace the page is not
/// followed, because "preview the thing you just made" and "browse the web"
/// are different features and the app has a separate browser for the second.
class WebPreviewScreen extends StatefulWidget {
  const WebPreviewScreen({super.key, required this.doc, this.title});

  final WebPreviewDoc doc;
  final String? title;

  @override
  State<WebPreviewScreen> createState() => _WebPreviewScreenState();
}

class _WebPreviewScreenState extends State<WebPreviewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  /// Errors the page itself raised. Without these a broken page is a white
  /// rectangle, and the user cannot tell a blank canvas from a crash.
  final _problems = <String>[];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            // Sub-resource failures are worth showing (a CDN that did not
            // load explains a dead page) but must not be treated as fatal.
            if (!mounted) return;
            setState(() {
              _loading = false;
              final line = e.description.trim();
              if (line.isNotEmpty && !_problems.contains(line)) {
                _problems.add(line);
              }
            });
          },
          onNavigationRequest: (req) {
            // The initial load is `about:blank`-ish and must be allowed; a
            // real URL means the page tried to navigate away.
            if (req.url.startsWith('http')) {
              _refuse(req.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(widget.doc.html);
  }

  void _refuse(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('This preview stayed put instead of opening $host.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _share() async {
    // Sharing the source, not a screenshot: it is the artefact the user can
    // move to a laptop, mail to themselves, or keep.
    await Share.share(widget.doc.html, subject: widget.title ?? 'Preview');
  }

  void _copy() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: widget.doc.html));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full page copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parts = widget.doc.partCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title ?? 'Preview',
                style: const TextStyle(fontSize: 16)),
            // Says the CSS and JS were folded in. Without it a three-block
            // reply looks like only the HTML ran.
            if (parts > 1)
              Text(
                '$parts blocks combined',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() {
                _loading = true;
                _problems.clear();
              });
              _controller.loadHtmlString(widget.doc.html);
            },
          ),
          IconButton(
            tooltip: 'Copy page',
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _share,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_problems.isNotEmpty)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(
                _problems.length == 1
                    ? _problems.first
                    : '${_problems.length} resources failed to load: '
                        '${_problems.take(2).join(' · ')}',
                style: AppTheme.mono(
                  fontSize: 11,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

/// Opens [doc] full-screen.
Future<void> showWebPreview(
  BuildContext context,
  WebPreviewDoc doc, {
  String? title,
}) {
  HapticFeedback.selectionClick();
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => WebPreviewScreen(doc: doc, title: title),
    ),
  );
}
