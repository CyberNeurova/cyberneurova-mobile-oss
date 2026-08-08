import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// One real browser, shared by the agent and the user.
///
/// ## Why a browser and not just `http_probe`
///
/// `http_probe` fetches bytes. That was enough when the web was documents, and
/// it is not enough now: a huge share of pages return an empty shell and build
/// their content in JavaScript, so a raw GET reads as "this page is blank" for
/// a page a person can plainly see. An agent that can only fetch bytes is
/// wrong about the modern web in a way it cannot detect.
///
/// A WebView runs the scripts. That is the whole difference.
///
/// ## And why the USER can see it
///
/// The same instance backs the browser screen. When the agent opens a page,
/// the user can look at exactly what it is looking at, scroll it, and take
/// over — sign in, dismiss a consent wall, solve whatever a bot cannot. Two
/// separate browsers would mean the agent's session and the user's session
/// have different cookies, and "log in for me" would silently not work.
///
/// It is the same principle the Console already runs on: one session, two
/// views, no hidden second context.
class AgentBrowser {
  AgentBrowser._();

  static final AgentBrowser instance = AgentBrowser._();

  WebViewController? _controller;

  /// Completes when the page in flight finishes loading.
  Completer<void>? _pending;

  String? _lastError;

  final ValueNotifier<String?> currentUrl = ValueNotifier(null);
  final ValueNotifier<String?> title = ValueNotifier(null);
  final ValueNotifier<bool> loading = ValueNotifier(false);

  /// The live controller, created on first use.
  ///
  /// Created lazily rather than at startup: a WebView is a heavyweight native
  /// object, and most sessions never open a page. Kept afterwards, because the
  /// cookies and the logged-in state ARE the value.
  WebViewController get controller {
    final existing = _controller;
    if (existing != null) return existing;

    final c = WebViewController();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            currentUrl.value = url;
            loading.value = true;
          },
          onPageFinished: (url) async {
            currentUrl.value = url;
            loading.value = false;
            title.value = await c.getTitle();
            _pending?.complete();
            _pending = null;
          },
          onWebResourceError: (error) {
            // Only the MAIN frame matters. A tracking pixel that 404s is not
            // a failed page load, and reporting it as one would have the agent
            // retry a page that rendered perfectly well.
            if (error.isForMainFrame != true) return;
            _lastError = '${error.errorCode} ${error.description}';
            loading.value = false;
            _pending?.complete();
            _pending = null;
          },
        ),
      );
    _controller = c;
    return c;
  }

  bool get hasSession => _controller != null;

  /// Loads [url] and waits for it to finish.
  ///
  /// Returns the error if the main frame failed, null on success. A timeout is
  /// success-ish on purpose: a page that never fires `onPageFinished` because
  /// of a long-polling connection is still perfectly readable, and refusing to
  /// read it would be worse than reading it slightly early.
  Future<String?> open(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _lastError = null;
    final done = Completer<void>();
    _pending = done;

    await controller.loadRequest(Uri.parse(url));
    await done.future.timeout(timeout, onTimeout: () {
      _pending = null;
      loading.value = false;
    });

    return _lastError;
  }

  /// The page's readable text, the way a person would see it.
  ///
  /// `innerText`, not `innerHTML`: the agent wants what the page says, and
  /// markup would spend the context window on div soup. Script and style
  /// elements are dropped for the same reason — `innerText` already excludes
  /// them, which is exactly why it beats `textContent` here.
  Future<String> readText({int maxChars = 12000}) async {
    if (_controller == null) return '';
    final raw = await controller.runJavaScriptReturningResult(
      '(function(){'
      'var m=document.querySelector("main")||document.querySelector("article");'
      'return (m||document.body).innerText;'
      '})()',
    );
    final text = _unwrap(raw);
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n\n[truncated at $maxChars chars]';
  }

  /// Every link on the page, as `text → href`.
  ///
  /// This is what makes the browser navigable rather than a dead end: without
  /// it the agent can read one page and has no idea what it can reach next,
  /// so it guesses URLs and 404s.
  Future<List<({String text, String href})>> readLinks({int max = 60}) async {
    if (_controller == null) return const [];
    final raw = await controller.runJavaScriptReturningResult(
      '(function(){'
      'return JSON.stringify([].slice.call(document.querySelectorAll("a[href]"))'
      '.map(function(a){return {t:(a.innerText||"").trim(),h:a.href};})'
      '.filter(function(x){return x.t&&x.h.indexOf("javascript:")!==0;})'
      '.slice(0,$max));'
      '})()',
    );
    try {
      final decoded = jsonDecode(_unwrap(raw)) as List;
      return [
        for (final e in decoded)
          (text: (e['t'] ?? '') as String, href: (e['h'] ?? '') as String),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Drops the browser and everything it remembers.
  ///
  /// The point is the cookies: "forget what I signed into" has to actually
  /// forget it, so this clears the store rather than only dropping the
  /// controller reference.
  Future<void> reset() async {
    await WebViewCookieManager().clearCookies();
    await _controller?.clearCache();
    await _controller?.clearLocalStorage();
    _controller = null;
    _pending = null;
    _lastError = null;
    currentUrl.value = null;
    title.value = null;
    loading.value = false;
  }

  /// `runJavaScriptReturningResult` returns a platform-dependent shape: a
  /// bare String on Android, a JSON-quoted String on iOS. Both arrive here.
  static String _unwrap(Object? raw) {
    var s = raw?.toString() ?? '';
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        return jsonDecode(s) as String;
      } catch (_) {
        s = s.substring(1, s.length - 1);
      }
    }
    return s.replaceAll(r'\n', '\n').trim();
  }
}
