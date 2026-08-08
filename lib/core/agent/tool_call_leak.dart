/// Keeps an unexecuted tool-call template from being shown as an answer.
///
/// ## The bug this exists for
///
/// When a model names a tool the server does not have, the call is refused and
/// the model falls back to emitting the call template as ordinary prose. That
/// string reaches the client inside a `result` frame flagged
/// `subtype:"success"`, so nothing upstream marks it as a failure and the app
/// renders it verbatim:
///
///     <|tool_call>call:Write{path:<|"|>hello.txt<|"|>,content:<|"|>hi<|"|>}<tool_call|>
///
/// Seen on prod 2026-08-04: Gemma emits `Write` where the registered tool is
/// `file_write`. The naming mismatch is the backend's to fix and is filed as
/// internal notes — but the app should not be showing raw template text to a user
/// under any circumstance, whatever the server sends. This is the same class
/// as the identity leak, and the same answer: guard it at the point of
/// rendering rather than hoping every producer is well-behaved.
///
/// ## Why this is not the server's stripper
///
/// There is one at the chat choke point, and it does not catch this shape —
/// the `<|…|>` delimiters and the `<|"|>` quoting are Gemma's own template,
/// not the `call:Skill{…}` form that stripper was written against. Both are
/// handled here so the app is covered whichever a model reaches for.
library;

/// What was in a chunk of assistant text once the templates were taken out.
class StrippedText {
  const StrippedText(this.text, this.toolNames);

  /// The prose that is safe to show. May be empty — see [isOnlyToolCall].
  final String text;

  /// Names of the calls that were removed, in the order they appeared.
  ///
  /// Kept rather than counted so the UI can say WHICH tool the model reached
  /// for. "Tried to use Write" is something a user can report; "a tool call
  /// failed" is not.
  final List<String> toolNames;

  bool get didStrip => toolNames.isNotEmpty;

  /// The model said nothing but the template.
  ///
  /// This is the case worth surfacing: there is no answer underneath, so
  /// rendering the stripped text alone would leave an empty bubble and the
  /// user would think the app broke rather than the call.
  bool get isOnlyToolCall => didStrip && text.trim().isEmpty;
}

/// Matches either delimiter spelling: `<|tool_call>` and `<tool_call|>` are
/// both used by the same template, and `<|tool_call|>` shows up too.
final _delimiter = RegExp(r'<\|?tool_call\|?>');

final _thinkBlock = RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
final _thinkOpen = RegExp(r'<think>[\s\S]*$', caseSensitive: false);
final _thinkClose = RegExp(r'^\s*</think>', caseSensitive: false);

/// Removes reasoning scaffolding from assistant text.
///
/// A reasoning model's private thinking is delimited by `<think>` tags that
/// the serving layer is supposed to strip. When it strips the opener but not
/// the closer — which is what happens when the reasoning is emitted before the
/// first content block — a bare `</think>` is left sitting at the top of the
/// reply. Observed on prod as the entire visible answer.
///
/// Handles the closer alone, a whole block, and an opener with no closer yet
/// (the streaming case, where showing the reasoning would leak it).
String stripThinkTags(String input) {
  if (!input.contains('think')) return input;
  return input
      .replaceAll(_thinkBlock, '')
      .replaceFirst(_thinkClose, '')
      .replaceFirst(_thinkOpen, '')
      .trim();
}

/// The quoting the template wraps around every value.
final _valueQuote = RegExp(r'<\|"\|>');

/// `<tool_code:Bash> … </tool_code>` — a third dialect from the same model.
///
/// Gemma reaches for whichever call syntax it was trained on and they are not
/// interchangeable: this one names the tool in the OPENING tag and puts a bare
/// command in the body, where the others carry a `call:` head and braces.
final _toolCode = RegExp(
  r'<tool_code(?::([A-Za-z_][A-Za-z0-9_]*))?>([\s\S]*?)(?:</tool_code>|$)',
  caseSensitive: false,
);

/// `call:Name{` — the head of a bare template, with no delimiters around it.
final _bareCall = RegExp(r'(^|\s)call:([A-Za-z_][A-Za-z0-9_]*)\s*\{');

/// `[system: …]` — an instruction the server injects for the MODEL.
///
/// When a call fails to parse, the serving layer feeds the model a correction:
/// "your shell_exec tool call could not be parsed and did not run — re-issue
/// it as a tool_code:ToolName block…". That is machine-to-machine text, and it
/// arrives in the assistant stream, so it renders as the answer. The user is
/// then reading instructions addressed to something else, about a failure they
/// have no way to act on.
///
/// Same family as the call templates and `</think>`: scaffolding that belongs
/// to the plumbing rather than the conversation.
final _systemDirective =
    RegExp(r'\[system:[\s\S]*?(?:\]|$)', caseSensitive: false);

/// Strips a server-injected `[system: …]` directive.
String stripSystemDirectives(String input) {
  if (!input.contains('[system:')) return input;
  return input.replaceAll(_systemDirective, '').trim();
}

/// Removes tool-call templates from assistant text.
///
/// Handles the delimited form, the bare `call:Name{…}` form, and — because
/// this runs on every partial frame of a stream — a template that has only
/// been half-written. Without that last case the opening delimiter and a
/// half-spelled tool name flash on screen before the closing one arrives.
StrippedText stripToolCallTemplates(String input) {
  if (!input.contains('call') && !input.contains('tool_code')) {
    return StrippedText(input, const []);
  }

  final names = <String>[];
  var text = input;

  // The `<tool_code:…>` dialect first: it is self-delimiting, so taking it out
  // cannot disturb the others. Unterminated matches to end of string, which is
  // the streaming case.
  for (final m in _toolCode.allMatches(text).toList().reversed) {
    names.insert(0, m.group(1) ?? 'a tool');
    text = text.substring(0, m.start) + text.substring(m.end);
  }

  // Delimited form first: it may CONTAIN a bare call, and taking the outer
  // form out first means the inner one is never seen twice.
  while (true) {
    final open = _delimiter.firstMatch(text);
    if (open == null) break;

    final close = _delimiter.firstMatch(text.substring(open.end));
    final body = close == null
        // Unterminated: the rest of the string is a template still being
        // written. Everything after the opener goes.
        ? text.substring(open.end)
        : text.substring(open.end, open.end + close.start);

    final named = _bareCall.firstMatch(body) ??
        RegExp(r'^\s*call:([A-Za-z_][A-Za-z0-9_]*)').firstMatch(body);
    if (named != null) {
      names.add(named.groupCount >= 2 ? named.group(2)! : named.group(1)!);
    }

    text = close == null
        ? text.substring(0, open.start)
        : text.substring(0, open.start) +
            text.substring(open.end + close.end);
  }

  // Bare form: scan the braces rather than regex them, because a value can
  // contain a brace and a lazy match would stop at the first one.
  while (true) {
    final head = _bareCall.firstMatch(text);
    if (head == null) break;

    final open = text.indexOf('{', head.start);
    final end = _matchingBrace(text, open);
    names.add(head.group(2)!);

    // No closing brace means it is still streaming; drop the tail.
    text = end == null
        ? text.substring(0, head.start + head.group(1)!.length)
        : text.substring(0, head.start + head.group(1)!.length) +
            text.substring(end + 1);
  }

  if (names.isEmpty) return StrippedText(input, const []);

  return StrippedText(text.replaceAll(_valueQuote, '').trim(), names);
}

/// Index of the `}` closing the `{` at [open], or null if it never closes.
int? _matchingBrace(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}
