import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cyberneurova_mobile/core/agent/device/agent_browser.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// The browser the agent is using, on screen.
///
/// ## Why the user gets to see it
///
/// An agent browsing invisibly is unauditable: it reports what a page said and
/// there is no way to check. Worse, it gets stuck in ways only a person can
/// clear — a sign-in, a cookie wall, a bot check — and from outside that looks
/// like the page simply having no content.
///
/// This is the same [AgentBrowser] instance, so it is the same cookie jar. The
/// user signs in here and the agent's next `browser_open` is signed in too.
/// Two browsers would make "log in for me" quietly not work, which is worse
/// than not offering it.
class AgentBrowserScreen extends StatefulWidget {
  const AgentBrowserScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<AgentBrowserScreen> createState() => _AgentBrowserScreenState();
}

class _AgentBrowserScreenState extends State<AgentBrowserScreen> {
  final _browser = AgentBrowser.instance;
  late final TextEditingController _address;

  /// Whether the history buttons can actually do anything.
  ///
  /// They used to be permanently enabled and check `canGoBack()` on tap, so
  /// with no history they were dead buttons that silently did nothing — the
  /// user's only feedback being that the screen did not change.
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(
      text: widget.initialUrl ?? _browser.currentUrl.value ?? '',
    );
    _browser.currentUrl.addListener(_refreshHistory);
    final start = widget.initialUrl;
    if (start != null && start.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _go(start));
    }
  }

  Future<void> _refreshHistory() async {
    final back = await _browser.controller.canGoBack();
    final forward = await _browser.controller.canGoForward();
    if (!mounted) return;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  @override
  void dispose() {
    _browser.currentUrl.removeListener(_refreshHistory);
    _address.dispose();
    super.dispose();
  }

  Future<void> _go(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    // Anything without a dot is a query, not a host. Typing "flutter docs"
    // into an address bar and getting "could not resolve" is a worse answer
    // than searching for it.
    final looksLikeUrl = text.contains('://') ||
        (text.contains('.') && !text.contains(' '));
    final url = looksLikeUrl
        ? (text.contains('://') ? text : 'https://$text')
        : 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(text)}';
    await _browser.open(url);
    if (mounted) _address.text = _browser.currentUrl.value ?? url;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          onSubmitted: _go,
          style: AppTheme.mono(fontSize: 12.5, color: cs.onSurface),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            hintText: 'Search or enter address',
            hintStyle: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'reload':
                  await _browser.controller.reload();
                case 'agentview':
                  final text = await _browser.readText(maxChars: 4000);
                  if (!context.mounted) return;
                  await showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (ctx) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.7,
                      builder: (_, scroll) => Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: SingleChildScrollView(
                          controller: scroll,
                          child: SelectableText(
                            text.isEmpty
                                ? 'This page rendered no readable text. That '
                                    'usually means it is still loading, or it '
                                    'is behind a wall only you can clear.'
                                : text,
                            style: AppTheme.mono(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ),
                    ),
                  );
                case 'forget':
                  await _browser.reset();
                  if (mounted) {
                    _address.clear();
                    setState(() {});
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reload', child: Text('Reload')),
              // Auditability: an agent reporting what a page said is only
              // checkable if the user can see the same extraction. It also
              // answers "why did it miss that" — usually because the text is
              // behind a wall the agent cannot clear.
              PopupMenuItem(
                  value: 'agentview', child: Text('What the agent sees')),
              // Named for what it does to the user, not for the mechanism.
              // "Clear cookies" describes the implementation; "Forget what I
              // signed into" describes the consequence they care about.
              PopupMenuItem(
                  value: 'forget', child: Text('Forget signed-in sites')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ValueListenableBuilder<bool>(
            valueListenable: _browser.loading,
            builder: (_, loading, __) => loading
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox(height: 2),
          ),
        ),
      ),
      body: Column(
        children: [
          _AgentBanner(browser: _browser),
          Expanded(
            // A browser that has loaded nothing is a white void with an
            // address bar above it — no indication of what it is or what to
            // do. The WebView stays mounted underneath so its cookies and
            // logged-in state survive; the empty state just covers it until
            // there is a page.
            child: ValueListenableBuilder<String?>(
              valueListenable: _browser.currentUrl,
              builder: (context, url, child) => Stack(
                children: [
                  Positioned.fill(child: child!),
                  if (url == null || url.isEmpty)
                    Positioned.fill(child: _Start(onGo: _go)),
                ],
              ),
              child: WebViewWidget(controller: _browser.controller),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.3))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: _canBack
                    ? () async {
                        await _browser.controller.goBack();
                        await _refreshHistory();
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                onPressed: _canForward
                    ? () async {
                        await _browser.controller.goForward();
                        await _refreshHistory();
                      }
                    : null,
              ),
              // Reload lived in the overflow menu, which is two taps for the
              // control a browser needs most often after back.
              IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => _browser.controller.reload(),
              ),
              IconButton(
                tooltip: 'Copy address',
                icon: const Icon(Icons.link_rounded, size: 20),
                onPressed: () {
                  final url = _browser.currentUrl.value;
                  if (url == null) return;
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Address copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Says out loud that this is shared with the agent.
class _AgentBanner extends StatelessWidget {
  const _AgentBanner({required this.browser});

  final AgentBrowser browser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 14, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The agent uses this browser too. Sign in here and it stays '
              'signed in for it.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the browser shows before it has been anywhere.
class _Start extends StatelessWidget {
  const _Start({required this.onGo});

  final Future<void> Function(String) onGo;

  /// Starting points, not bookmarks.
  ///
  /// The point of this browser is that a sign-in here is a sign-in for the
  /// agent, so the useful destinations are the ones worth being signed in to.
  static const _suggestions = <(String, String)>[
    ('GitHub', 'https://github.com'),
    ('Hacker News', 'https://news.ycombinator.com'),
    ('CVE search', 'https://nvd.nist.gov/vuln/search'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        child: Column(
          children: [
            Icon(Icons.public_rounded, size: 34, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              'Nothing open yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Type an address above, or start somewhere. Pages you sign in '
              'to here stay signed in when the agent opens them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            for (final (label, url) in _suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onGo(url);
                  },
                  child: Row(
                    children: [
                      Icon(Icons.north_east_rounded,
                          size: 15, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Text(label,
                          style:
                              TextStyle(fontSize: 14, color: cs.onSurface)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
