/// Turning the web code in a reply into something the user can actually run.
///
/// ## The report this exists for
///
/// The owner, verbatim: *"it didn't implement the preview — it just wrote code
/// and I could not use the HTML game it created."* That is the whole gap. On a
/// laptop you paste three blocks into a file and open it; on a phone there is
/// nowhere to paste them and nothing to open them with, so a working game
/// arrives as text and dies there.
///
/// ## Why assembling is the hard part, not the webview
///
/// Models almost never emit one self-contained file. They emit an HTML block
/// that says `<link rel="stylesheet" href="style.css">` and then, separately, a
/// CSS block — which is correct advice for someone with a filesystem and
/// useless to a WebView handed a single string. So this stitches the reply's
/// blocks back into one document: CSS into `<head>`, JS before `</body>`, and
/// the dangling references to files that will never exist removed.
///
/// It is deliberately conservative about what counts as runnable. Offering
/// "Run" on a Python script the phone cannot execute would be a dead button,
/// and a dead button is worse than no button.
library;

/// One fenced block from a reply.
typedef CodeBlock = ({String? language, String code});

/// A runnable document assembled from a reply's code blocks.
class WebPreviewDoc {
  const WebPreviewDoc({
    required this.html,
    required this.anchorIndex,
    required this.partCount,
  });

  /// The complete, self-contained document.
  final String html;

  /// Which block the Run action belongs on — the HTML one, since that is the
  /// block the user is looking at when they think "can I see this".
  final int anchorIndex;

  /// How many blocks were folded in, including the HTML. Shown to the user so
  /// a three-block reply does not look like the CSS was ignored.
  final int partCount;
}

/// Assembles [blocks] into something runnable, or null if nothing here is.
WebPreviewDoc? assembleWebPreview(List<CodeBlock> blocks) {
  final htmlIndex = blocks.indexWhere((b) => _isHtml(b));
  if (htmlIndex < 0) return null;

  var html = blocks[htmlIndex].code.trim();
  if (html.isEmpty) return null;

  final css = <String>[];
  final js = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i == htmlIndex) continue;
    final lang = (blocks[i].language ?? '').toLowerCase();
    if (lang == 'css') css.add(blocks[i].code);
    if (lang == 'js' || lang == 'javascript') js.add(blocks[i].code);
  }

  // A fragment — `<div class="board">…` with no document around it — is common
  // when the model is showing "the markup" rather than a file. It renders as
  // nothing useful without a skeleton.
  if (!_hasDocumentShell(html)) {
    html = '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '</head><body>\n$html\n</body></html>';
  }

  // These point at files that will never exist here, and a browser handed a
  // dead <link> silently renders the page unstyled — which reads as "the
  // preview is broken" rather than "that file isn't real".
  html = _dropLocalRefs(html);

  if (css.isNotEmpty) {
    html = _injectBefore(html, '</head>',
        '<style>\n${css.join('\n\n')}\n</style>\n');
  }
  if (js.isNotEmpty) {
    html = _injectBefore(html, '</body>',
        '<script>\n${js.join('\n\n')}\n</script>\n');
  }

  return WebPreviewDoc(
    html: html,
    anchorIndex: htmlIndex,
    partCount: 1 + css.length + js.length,
  );
}

/// Whether this block is the HTML one.
///
/// Trusts the fence label when it is there and sniffs the content when it is
/// not — models label maybe half the time, and an unlabelled `<!doctype html>`
/// is not ambiguous.
bool _isHtml(CodeBlock b) {
  final lang = (b.language ?? '').toLowerCase();
  if (lang == 'html' || lang == 'htm') return true;
  if (lang.isNotEmpty && lang != 'markup') return false;

  final head = b.code.trimLeft().toLowerCase();
  return head.startsWith('<!doctype html') ||
      head.startsWith('<html') ||
      (head.startsWith('<') && head.contains('</'));
}

final _shellRe = RegExp(r'<html[\s>]|<body[\s>]', caseSensitive: false);
bool _hasDocumentShell(String html) => _shellRe.hasMatch(html);

/// Strips `<link>` and `<script src>` that point at sibling files.
///
/// Only local ones: a CDN URL is a real resource the WebView can fetch, and
/// removing it would break exactly the pages that were correct.
String _dropLocalRefs(String html) {
  final link = RegExp(
    r'''<link\b[^>]*\shref\s*=\s*["'](?!https?:|//|data:)[^"']*["'][^>]*>''',
    caseSensitive: false,
  );
  final script = RegExp(
    r'''<script\b[^>]*\ssrc\s*=\s*["'](?!https?:|//|data:)[^"']*["'][^>]*>\s*</script>''',
    caseSensitive: false,
  );
  return html.replaceAll(link, '').replaceAll(script, '');
}

/// Inserts [fragment] before [tag], appending if the tag is absent.
String _injectBefore(String html, String tag, String fragment) {
  final at = html.toLowerCase().lastIndexOf(tag);
  if (at < 0) return '$html\n$fragment';
  return html.substring(0, at) + fragment + html.substring(at);
}
