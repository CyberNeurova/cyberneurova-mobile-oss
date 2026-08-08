/// Turns a user's first message into a session name.
///
/// The server does this for plain chats; agent sessions never reach it, so the
/// client has to do the same job to avoid a list of identical "New Chat" rows.
/// The rules are the boring ones that make a list scannable on a phone: one
/// line, no markdown, no trailing full stop, and short enough to read at a
/// glance in a row that is also showing a timestamp.
library;

const _maxLength = 44;

/// Titles that are not names — the server's placeholder for a chat nobody has
/// spoken in yet, plus the ones we might set ourselves.
bool isPlaceholderChatTitle(String title) {
  final t = title.trim().toLowerCase();
  return t.isEmpty || t == 'new chat' || t == 'untitled' || t == 'new session';
}

/// True when a title has nothing a person could read as a name.
///
/// Empty and the known placeholders, plus anything with no letters or digits
/// at all. A Research session showed up in the list as **"??"** — a real,
/// non-empty title that says nothing, because the query itself was punctuation
/// and the only guard was `isEmpty`.
///
/// Unicode-aware on purpose: `\w` is ASCII in Dart, so a Chinese or Arabic
/// title would have been judged unreadable and thrown away. Several memories
/// on this account are in Chinese; this list will be too.
bool isUnusableTitle(String title) =>
    isPlaceholderChatTitle(title) ||
    !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(title);

/// What to call a session in a list.
///
/// "New Chat" is the server's placeholder and reads like a button, not a name;
/// a list of five of them tells the user nothing about which session is which.
/// A session that has been spoken in gets titled from its first message, so
/// anything still holding the placeholder here genuinely has no name — say so
/// rather than pretending.
String sessionDisplayTitle(String title) =>
    isUnusableTitle(title) ? 'Untitled session' : title.trim();

String titleFromMessage(String message) {
  var text = message.trim();
  if (text.isEmpty) return '';

  // A message that opens with a code fence has nothing quotable in it; take
  // whatever prose came after instead of naming the session "```dart".
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');

  // First non-empty line. A long paste's later lines say nothing a title can
  // use, and the opening line is what the user actually asked for.
  final line = text
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return '';

  var t = line
      // Leading markdown furniture: bullets, quotes, headings.
      .replaceFirst(RegExp(r'^[>#*\-\s]+'), '')
      // Inline code / emphasis markers read as noise at title size.
      .replaceAll(RegExp(r'[`*_]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return '';

  // Stop at the first sentence end if that already gives us something
  // substantial — "create clock.html. make it dark" titles better as the ask.
  final stop = RegExp(r'[.!?](\s|$)').firstMatch(t);
  if (stop != null && stop.start >= 12 && stop.start < _maxLength) {
    t = t.substring(0, stop.start).trim();
  }

  var truncated = false;
  if (t.length > _maxLength) {
    final cut = t.lastIndexOf(' ', _maxLength);
    t = t.substring(0, cut > 16 ? cut : _maxLength);
    truncated = true;
  }

  // Trailing punctuation left over from truncation or the original line —
  // stripped BEFORE the ellipsis so we never produce "do this,…".
  t = t.replaceFirst(RegExp(r'[\s,;:.!?-]+$'), '');
  if (t.isEmpty) return '';
  if (truncated) t = '$t…';

  return t[0].toUpperCase() + t.substring(1);
}
