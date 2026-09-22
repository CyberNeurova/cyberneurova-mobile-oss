import 'dart:async';
import 'dart:convert';

import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';

/// In-memory [ChatRepository] used when [devAuthBypass] is on — lets the whole
/// chat UI (welcome hint, typing indicator, token streaming, markdown/code
/// bubbles, Continue pill, drawer recents) run with no account and no network.
/// State lives for the process lifetime only.
class DevMockChatRepository extends ChatRepository {
  DevMockChatRepository(super.client);

  int _idSeq = 0;
  String _newId(String prefix) => '$prefix-dev-${++_idSeq}';

  late final Map<String, ChatModel> _chats = {
    for (final c in _seedChats) c.id: c,
  };
  late final Map<String, List<MessageModel>> _messages = {
    'chat-dev-fresh': [],
    'chat-dev-markdown': _markdownShowcase,
    'chat-dev-code': _codeShowcase,
  };

  static final _seedChats = <ChatModel>[
    ChatModel(
      id: 'chat-dev-fresh',
      title: 'New chat',
      messageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    ChatModel(
      id: 'chat-dev-markdown',
      title: 'Markdown & math showcase',
      messageCount: 4,
      lastMessage: 'Here is everything the renderer supports…',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    ChatModel(
      id: 'chat-dev-code',
      title: 'Code panel showcase',
      messageCount: 2,
      lastMessage: 'A widget that debounces its onChanged…',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  static final _markdownShowcase = <MessageModel>[
    const MessageModel(
      id: 'm-dev-1',
      chatId: 'chat-dev-markdown',
      role: 'user',
      content: 'Show me what your markdown rendering can do — lists, tables, '
          'math, the lot.',
    ),
    const MessageModel(
      id: 'm-dev-2',
      chatId: 'chat-dev-markdown',
      role: 'assistant',
      modelName: 'NeurovaX-Large',
      content: '''
## Everything the renderer supports

Here's a quick tour. **Bold**, *italic*, `inline code`, and [links](https://cyberneurova.ai).

1. Ordered lists
2. With multiple items
   - and nested bullets
   - like this one

> Blockquotes render with a left rule and muted text.

| Feature | Status |
|---|---|
| Tables | ✓ |
| Math | ✓ |

Display math (double-dollar blocks — note the renderer splits on them
even inside inline code, so don't quote the delimiters literally):

\$\$\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}\$\$

That's the whole tour — ask for a code sample to see the code panel.''',
    ),
    const MessageModel(
      id: 'm-dev-3',
      chatId: 'chat-dev-markdown',
      role: 'user',
      content: 'Nice. And how do long user messages wrap? Here is a fairly '
          'long question that should wrap across several lines inside the '
          'user bubble so we can check padding, line height, and the max '
          'width constraint on small screens.',
    ),
    const MessageModel(
      id: 'm-dev-4',
      chatId: 'chat-dev-markdown',
      role: 'assistant',
      modelName: 'NeurovaX-Large',
      content:
          'They wrap exactly like this reply — assistant text sits directly '
          'on the background with no bubble (Variant A), while your messages '
          'get the soft rounded rectangle on the right. Generous line height '
          'keeps multi-paragraph replies readable.\n\nSecond paragraph to '
          'check paragraph spacing.',
    ),
  ];

  static final _codeShowcase = <MessageModel>[
    const MessageModel(
      id: 'm-dev-5',
      chatId: 'chat-dev-code',
      role: 'user',
      content: 'Write a Flutter widget that debounces its onChanged callback.',
    ),
    const MessageModel(
      id: 'm-dev-6',
      chatId: 'chat-dev-code',
      role: 'assistant',
      modelName: 'NeurovaX-Large',
      content: '''
A `Timer`-based debounce, cancelled on every keystroke:

```dart
class DebouncedField extends StatefulWidget {
  const DebouncedField({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<DebouncedField> createState() => _DebouncedFieldState();
}

class _DebouncedFieldState extends State<DebouncedField> {
  Timer? _debounce;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onChanged(value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(onChanged: _onChanged);
  }
}
```

The important part is cancelling the pending timer before arming a new one.''',
    ),
  ];

  // ── Chats ────────────────────────────────────────────────────────────────

  @override
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    await Future.delayed(const Duration(milliseconds: 250));
    // Filters like the real server does, so the sandbox exercises the same
    // per-section paths the device does rather than handing every caller the
    // whole store back.
    final chats = _chats.values
        .where((c) => section == null || c.section == section)
        .toList()
      ..sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0))
          .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(0)));
    return ChatListResponse(chats: chats);
  }

  @override
  Future<ChatModel> createChat({String? title, String section = 'chat'}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final chat = ChatModel(
      id: _newId('chat'),
      title: title ?? 'New chat',
      section: section,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _chats[chat.id] = chat;
    _messages[chat.id] = [];
    return chat;
  }

  @override
  Future<({ChatModel chat, List<MessageModel> messages})> getChatWithMessages(
    String id,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final chat = _chats[id] ?? ChatModel(id: id, title: 'New chat');
    return (
      chat: chat,
      messages: List.of(_messages[id] ?? const <MessageModel>[]),
    );
  }

  @override
  Future<MessagesResponse> getMessages(
    String chatId, {
    String? cursor,
    int limit = 30,
  }) async {
    return MessagesResponse(
      messages: List.of(_messages[chatId] ?? const <MessageModel>[]),
    );
  }

  @override
  Future<ChatModel> updateChat(String id,
      {String? title, String? visibility}) async {
    final updated = (_chats[id] ?? ChatModel(id: id)).copyWith(
      title: title ?? _chats[id]?.title ?? '',
      visibility: visibility ?? _chats[id]?.visibility ?? 'private',
      updatedAt: DateTime.now(),
    );
    _chats[id] = updated;
    return updated;
  }

  @override
  Future<void> deleteChat(String id) async {
    _chats.remove(id);
    _messages.remove(id);
  }

  @override
  Future<void> updateVisibility(String chatId, String visibility) async {}

  @override
  Future<void> shareWithEmail(String chatId, String email) async {}

  @override
  Future<void> unshareWithEmail(String chatId, String email) async {}

  @override
  Future<Map<String, dynamic>> getShareInfo(String chatId) async =>
      {'sharedWith': <String>[]};

  // ── Streaming ────────────────────────────────────────────────────────────

  /// Fake token stream. Special prompts to exercise specific UI:
  ///   - contains "search"   → emits web-search status events first
  ///   - contains "truncate" → ends with `truncated: true` (Continue pill)
  ///   - contains "agent"    → simulated agentic run: live 'tool-running'
  ///     statuses, then a reply embedding a `[TOOL_RUN:{json}]` marker
  ///     (inbox/025) rendered as a ToolRunCard
  @override
  Stream<StreamEvent> streamCompletion({
    required String chatId,
    required String message,
    String modelId = 'tiny-neurova',
    List<Map<String, dynamic>>? attachments,
    bool forceWebSearch = false,
    String? deviceContext,
  }) async* {
    final messageId = _newId('msg');
    final wantSearch =
        forceWebSearch || message.toLowerCase().contains('search');
    final wantTruncate = message.toLowerCase().contains('truncate');
    final wantAgent = message.toLowerCase().contains('agent');

    await Future.delayed(const Duration(milliseconds: 400));
    yield StreamEvent.start(messageId: messageId, model: modelId);

    if (wantSearch) {
      yield StreamEvent.status(status: 'web-searching', query: message);
      await Future.delayed(const Duration(milliseconds: 900));
      yield const StreamEvent.status(
          status: 'web-searched', resultCount: 8, source: 'searxng');
    }

    if (wantAgent) {
      // Live tool activity — surfaced by the typing indicator's spinner line.
      yield const StreamEvent.status(
          status: 'tool-running', query: 'Reading pubspec.yaml');
      await Future.delayed(const Duration(milliseconds: 900));
      yield const StreamEvent.status(
          status: 'tool-running', query: 'Running flutter analyze');
      await Future.delayed(const Duration(milliseconds: 900));
      yield const StreamEvent.status(
          status: 'tool-running', query: 'Editing main.py');
      await Future.delayed(const Duration(milliseconds: 700));
      yield const StreamEvent.status(status: 'tool-done');
    }

    final buffer = StringBuffer();
    // Stream in small word-group chunks so streaming feels real. The agent
    // reply emits its [TOOL_RUN:{json}] marker as ONE chunk so the card
    // appears atomically instead of flashing partial JSON mid-stream.
    final chunks = wantAgent
        ? [
            ..._wordChunks(_agentIntro),
            '[TOOL_RUN:$_agentToolRunJson]',
            ..._wordChunks(_agentOutro),
          ]
        : _wordChunks(_replyFor(message, truncated: wantTruncate));
    for (final chunk in chunks) {
      buffer.write(chunk);
      yield StreamEvent.token(content: chunk);
      await Future.delayed(const Duration(milliseconds: 45));
    }

    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.addAll([
      MessageModel(
        id: _newId('msg'),
        chatId: chatId,
        role: 'user',
        content: message,
      ),
      MessageModel(
        id: messageId,
        chatId: chatId,
        role: 'assistant',
        modelName: modelId,
        content: buffer.toString().trimRight(),
      ),
    ]);
    _chats[chatId] = (_chats[chatId] ?? ChatModel(id: chatId)).copyWith(
      messageCount: _messages[chatId]!.length,
      lastMessage: message,
      updatedAt: DateTime.now(),
    );

    yield StreamEvent.usage(
        inputTokens: 42,
        outputTokens: chunks.length * 3,
        totalTokens: 42 + chunks.length * 3);
    yield StreamEvent.done(
      messageId: messageId,
      finishReason: wantTruncate ? 'length' : 'stop',
      truncated: wantTruncate,
    );
  }

  @override
  Stream<StreamEvent> streamResume({
    required String chatId,
    required String messageId,
  }) async* {
    await Future.delayed(const Duration(milliseconds: 400));
    yield StreamEvent.start(messageId: messageId, mode: 'resume');
    const continuation =
        '…and this is the continuation streaming into the SAME bubble after '
        'you tapped Continue. No new bubble, no repeated preamble — exactly '
        'how the resume endpoint behaves in production.';
    for (final word in continuation.split(' ')) {
      yield StreamEvent.token(content: '$word ');
      await Future.delayed(const Duration(milliseconds: 45));
    }
    yield StreamEvent.done(
        messageId: messageId, finishReason: 'stop', mode: 'resume');
  }

  /// Splits [text] into 3-word streaming chunks (trailing space each, same
  /// contract as the original inline loop — accumulated text is trimRight'd
  /// before persisting).
  static List<String> _wordChunks(String text) {
    final words = text.split(' ');
    return [
      for (var i = 0; i < words.length; i += 3)
        '${words.sublist(i, (i + 3 > words.length) ? words.length : i + 3).join(' ')} ',
    ];
  }

  // ── Agent magic-prompt fixtures (inbox/025) ─────────────────────────────

  static const _agentIntro =
      "I ran an agentic pass over the workspace — here's the full activity log:\n\n";

  static const _agentOutro =
      '\n\n`flutter test` failed because `compute()` raises on empty input — '
      '`main.py` now validates its arguments and exits with a proper status '
      'code instead. Tap the card above to inspect each step, and the edit '
      'step to view the unified diff.';

  /// Small realistic unified diff: 12 added, 4 removed — matches the edit
  /// step's `added`/`removed` badges.
  static const _agentDiff = '''--- a/main.py
+++ b/main.py
@@ -1,6 +1,14 @@
 import sys

-def main():
-    data = load(sys.argv[1])
-    result = compute(data)
-    print(result)
+def main() -> int:
+    if len(sys.argv) < 2:
+        print("usage: main.py <input>", file=sys.stderr)
+        return 2
+    data = load(sys.argv[1])
+    try:
+        result = compute(data)
+    except ValueError as err:
+        print(f"compute failed: {err}", file=sys.stderr)
+        return 1
+    print(result)
+    return 0''';

  /// `[TOOL_RUN:{json}]` payload: 2 runs (1 failed), 2 reads, 1 edit with a
  /// tappable diff. Every step carries an `output` (file-content preview /
  /// command stdout) so the per-step detail sheet has something to show.
  /// jsonEncode keeps the newlines in `diff`/`output` escaped so the marker
  /// parser's jsonDecode round-trips it cleanly.
  static final _agentToolRunJson = jsonEncode({
    'steps': [
      {
        'verb': 'read',
        'target': 'pubspec.yaml',
        'output': 'name: cyberneurova_mobile\n'
            'description: CyberNeurova AI assistant client.\n'
            'version: 1.4.2+58\n'
            '\n'
            'environment:\n'
            "  sdk: '>=3.4.0 <4.0.0'",
      },
      {
        'verb': 'read',
        'target': 'lib/main.py',
        'output': 'import sys\n'
            '\n'
            'def main():\n'
            '    data = load(sys.argv[1])\n'
            '    result = compute(data)\n'
            '    print(result)',
      },
      {
        'verb': 'run',
        'target': 'flutter analyze',
        'output': 'Analyzing cyberneurova_mobile...\n'
            '\n'
            '   info - Unused import - lib/legacy/consent.dart:3 - unused_import\n'
            '\n'
            '1 issue found. (ran in 4.2s)',
      },
      {
        'verb': 'run',
        'target': 'flutter test',
        'failed': true,
        'error': 'Exit code 1 — 2 of 14 tests failed in test/app_test.dart',
        'output':
            '00:04 +12 -2: test/app_test.dart: compute handles empty input [E]\n'
                '  Invalid argument(s): input must not be empty\n'
                '  test/app_test.dart 42:7  main.<fn>\n'
                '00:04 +12 -2: Some tests failed.',
      },
      {
        'verb': 'edit',
        'target': 'main.py',
        'added': 12,
        'removed': 4,
        'diff': _agentDiff,
      },
    ],
  });

  String _replyFor(String message, {required bool truncated}) {
    if (truncated) {
      return 'This reply is deliberately cut short by the mock server to '
          'exercise the truncation flow. The done event carries '
          '`truncated: true`, so the Continue pill should appear right below '
          'this bubble — tap it and the resume stream appends';
    }
    return '''
Mock reply to: "$message"

This is the **dev sandbox** (`DEV_AUTH_BYPASS=true`) — no network, no account. Try these prompts to exercise specific UI:

- `search anything` — web-search status events in the typing indicator
- `truncate` — a cut-off reply with the **Continue** pill
- `agent` — a simulated agentic run: live tool status, then a tool-run card with a tappable diff
- anything else — this reply, streamed word by word

Code sample for the code panel:

```python
def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

And a touch of math:

\$\$\\sigma(x) = \\frac{1}{1 + e^{-x}}\$\$''';
  }
}
