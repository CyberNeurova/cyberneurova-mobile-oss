/// Splits a markdown fence's info string from its body.
///
/// A fence opens as ```` ```bash ````, so the first line is the language —
/// but only when it is a bare word. Treating *any* first line as a tag would
/// silently eat a real line from a block that opened as a plain ``` fence,
/// which you would only notice after pasting a command that no longer works.
///
/// Its own function so it can be tested without a widget tree.
(String?, String) splitFence(String raw) {
  final text = raw.startsWith('\n') ? raw.substring(1) : raw;
  final nl = text.indexOf('\n');
  if (nl < 0) return (null, text.trim());

  final first = text.substring(0, nl).trim();
  final isTag = first.isNotEmpty &&
      first.length <= 16 &&
      RegExp(r'^[A-Za-z0-9+#._-]+$').hasMatch(first);

  return isTag
      ? (first.toLowerCase(), text.substring(nl + 1).trimRight())
      : (null, text.trimRight());
}
