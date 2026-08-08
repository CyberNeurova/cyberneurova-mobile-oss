import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/agent_session_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/fence.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/line_diff.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/diff_body.dart';

/// The Ask surface — a readable account of what the agent did.
///
/// The terminal is the ground truth and stays exactly as it is; this is the
/// *other* view of the same session. Raw PTY output is the wrong thing to read
/// on a phone: `apk add` alone is forty lines of fetch/install chatter, and
/// scrolling that to find the one sentence that matters is precisely what
/// makes a terminal painful on a small screen.
///
/// So commands become **cards** — command, status, timing, output collapsed
/// behind a line count — and the model's prose sits between them at full
/// width. Nothing is hidden, only folded: tapping a card shows every line, and
/// switching to Shell shows the unedited session.
class AskView extends ConsumerStatefulWidget {
  const AskView({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<AskView> createState() => _AskViewState();
}

class _AskViewState extends ConsumerState<AskView> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Id of the newest user message we have already scrolled to.
  String? _lastOwnMessageId;

  void _followTail(int count, {bool force = false}) {
    if (count == _lastCount && !force) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;

      // Your OWN message always wins. Sending something and watching the
      // screen not move reads as the send having failed — I mistook it for
      // exactly that twice while testing, and went looking for a bug in the
      // send path. Everything else stays stick-aware: yanking someone back
      // while they read an earlier result is the most irritating thing a
      // transcript can do.
      if (force || pos.maxScrollExtent - pos.pixels < 220) {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final messages =
        ref.watch(chatDetailProvider(widget.chatId)).valueOrNull?.messages ??
            const <MessageModel>[];
    final session = ref.watch(agentSessionProvider(widget.chatId));
    final tools = [
      for (final i in session.transcript.items)
        if (i is ToolCardItem) i,
    ];

    // Tapping the transcript lowers the keyboard — the convention every
    // messaging app already trained people on, and the only way to get the
    // keyboard down in Ask, which has no key row to hang a button off.
    // `opaque` so the empty area counts as a hit, not just the text.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: _content(cs, messages, tools),
    );
  }

  Widget _content(
    ColorScheme cs,
    List<MessageModel> messages,
    List<ToolCardItem> tools,
  ) {
    if (messages.isEmpty && tools.isEmpty) return _empty(cs);
    // A newly-arrived message of the user's own forces the jump.
    final lastOwn = messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => messages.first,
    );
    final ownIsNew =
        lastOwn.role == 'user' && lastOwn.id != _lastOwnMessageId;
    if (ownIsNew) _lastOwnMessageId = lastOwn.id;

    _followTail(messages.length + tools.length, force: ownIsNew);

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: _interleave(messages, tools),
    );
  }

  /// Puts each tool card where it was actually called.
  ///
  /// Everything used to render as all-prose-then-all-cards, on the reasoning
  /// that interleaving would reorder the reply as tokens arrived. With two or
  /// three cards that looked fine. With more it is wrong in a way that gets
  /// worse the more the agent does: the cards pile at the bottom, so they
  /// appear to belong to whatever message is newest — including one sent long
  /// after the work happened — and a fifty-call run becomes an unreadable wall
  /// detached from the turns that produced it.
  ///
  /// Ordered by `startedAt`, stamped once when the call opens and never moved.
  /// That is what makes it stable while streaming: the anchor is fixed before
  /// the text around it has finished arriving.
  List<Widget> _interleave(
    List<MessageModel> messages,
    List<ToolCardItem> tools,
  ) {
    final pending = [...tools]..sort((a, b) =>
        (a.startedAt ?? DateTime(0)).compareTo(b.startedAt ?? DateTime(0)));

    final out = <Widget>[];
    for (final m in messages) {
      // A call that began before this message belongs to the exchange above
      // it, so it goes first.
      while (pending.isNotEmpty &&
          (pending.first.startedAt ?? DateTime(0))
              .isBefore(m.createdAt ?? DateTime.now())) {
        out.add(_ToolCard(item: pending.removeAt(0)));
      }
      out.add(_Turn(message: m));
    }
    // Whatever is still open belongs to the turn in flight.
    out.addAll([for (final t in pending) _ToolCard(item: t)]);
    return out;
  }

  /// Scrollable, because the keyboard takes half the screen.
  ///
  /// A centred Column overflowed by a few pixels the moment the keyboard came
  /// up — Flutter paints that as the yellow-and-black tape the owner reported,
  /// across the middle of the first thing a new user reads.
  Widget _empty(ColorScheme cs) => SingleChildScrollView(
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 26, color: cs.primary),
              const SizedBox(height: 12),
              Text('Ask for what you want',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const SizedBox(height: 6),
              Text(
                'The agent works in this same session — same directory, same '
                'files. It runs what it needs in the Shell tab and reports '
                'back here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
}

class _Turn extends StatelessWidget {
  const _Turn({required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    if (message.content.trim().isEmpty) return const SizedBox.shrink();

    // Sides, the way every messaging app does it: yours on the right, the
    // agent's on the left. The old arrangement marked the user's turn with a
    // small arrow and left both sides flush left, which reads as one
    // continuous document rather than a conversation — and in a transcript
    // full of tool output and code it was genuinely hard to see who said
    // what. Position is the cue people already know; it costs no space and
    // needs no legend.
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 40),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                // Squared toward its own side — the tail convention, without
                // drawing a tail.
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              message.content.trim(),
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    // The agent's side is NOT wrapped in a bubble: replies here carry code
    // blocks, headings and tool output, and boxing those inside a rounded
    // container on a phone leaves about forty characters of usable width.
    // Left alignment and the full column carry the distinction on their own.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 24),
      child: _Prose(text: message.content),
    );
  }
}

/// Assistant text, rendered.
///
/// Models write markdown whether or not you ask them to, and showing it raw
/// puts `**Device:**`, `###` and bare `*` bullets on screen — which is the
/// opposite of readable, especially on a phone where every wasted character
/// costs a line.
///
/// Deliberately a small subset — bold, inline code, headings, bullets, fenced
/// blocks — rather than a markdown package. That is what the model actually
/// emits here, and a full renderer drags in link handling, tables and image
/// loading that would fight the terminal one tab away.
class _Prose extends StatelessWidget {
  const _Prose({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parts = text.split('```');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].trim().isNotEmpty)
            if (i.isEven)
              _Markdown(text: parts[i], scheme: cs)
            else
              _CodeBlock(raw: parts[i]),
      ],
    );
  }
}

/// Block-level pass: headings and bullets, each line's inline spans built by
/// [_inlineSpans].
class _Markdown extends StatelessWidget {
  const _Markdown({required this.text, required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final lines = text.trim().split('\n');
    final blocks = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(line.trimLeft());
      if (heading != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: SelectableText.rich(
            TextSpan(
              children: _inlineSpans(heading.group(2)!, scheme),
              style: TextStyle(
                // One size for every level. Six heading sizes is a document
                // convention; on a phone it just makes short sections shout.
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: scheme.onSurface,
              ),
            ),
          ),
        ));
        continue;
      }

      final bullet = RegExp(r'^\s*[-*+]\s+(.*)').firstMatch(line);
      if (bullet != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    children: _inlineSpans(bullet.group(1)!, scheme),
                    style: TextStyle(
                        fontSize: 14, height: 1.45, color: scheme.onSurface),
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SelectableText.rich(
          TextSpan(
            children: _inlineSpans(line, scheme),
            style:
                TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurface),
          ),
        ),
      ));
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }
}

/// Inline pass: `**bold**` and `` `code` ``.
///
/// One regex over both so they cannot nest badly — matching them separately
/// leaves the delimiters of whichever ran second sitting inside the other's
/// output.
List<TextSpan> _inlineSpans(String text, ColorScheme cs) {
  final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
  final spans = <TextSpan>[];
  var cursor = 0;

  for (final m in pattern.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    if (m.group(1) != null) {
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
    } else {
      spans.add(TextSpan(
        text: m.group(2),
        style: AppTheme.mono(
          fontSize: 12.5,
          color: cs.primary,
        ),
      ));
    }
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}

/// A fenced block from the model, with its language and a copy action.
///
/// Code and commands are the substance of an answer here, not decoration, so
/// they get a header that names the language and a one-tap copy — on a phone,
/// selecting a multi-line command by dragging is genuinely difficult, and
/// re-typing it into the Shell tab is worse.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (lang, body) = splitFence(raw);
    if (body.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 6, 5),
            child: Row(
              children: [
                Text(
                  lang ?? 'text',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                _CopyButton(text: body),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
            // Horizontal scroll, not wrapping: a wrapped command line is
            // ambiguous to read and impossible to copy correctly by eye. The
            // page itself must never scroll sideways, so it is confined here.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                body,
                style: AppTheme.mono(
                    fontSize: 12.5, height: 1.45, color: cs.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: _done ? 'Copied' : 'Copy code',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.text));
          if (!mounted) return;
          // Confirm in place. A snackbar would cover the answer being read,
          // and the whole point of the tap is to stay where you are.
          setState(() => _done = true);
          await Future<void>.delayed(const Duration(milliseconds: 1400));
          if (mounted) setState(() => _done = false);
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _done ? Icons.check_rounded : Icons.copy_rounded,
                size: 13,
                color: _done ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                _done ? 'Copied' : 'Copy',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _done ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One command the agent ran, folded.
/// A file edit, rendered as a diff.
///
/// Colour is not the only signal: every line keeps its leading `+`/`-`, so
/// this still reads correctly for someone who cannot distinguish the two
/// tints, and it survives being copied out as plain text.
class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.item});

  final ToolCardItem item;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = widget.item;

    final (Color tint, IconData icon) = switch (t.state) {
      ToolCardState.running || ToolCardState.pending => (
          cs.primary,
          Icons.play_arrow_rounded
        ),
      ToolCardState.succeeded => (cs.primary, Icons.check_rounded),
      ToolCardState.failed => (cs.error, Icons.close_rounded),
      ToolCardState.denied || ToolCardState.cancelled => (
          cs.onSurfaceVariant,
          Icons.block_rounded
        ),
      ToolCardState.approvalRequired => (
          cs.tertiary,
          Icons.lock_outline_rounded
        ),
    };

    // What the agent actually asked for. `command` for shell_exec, `target`
    // for the network tools — showing the raw JSON would be noise.
    final detail = (t.input['command'] ?? t.input['target'] ?? t.title ?? '')
        .toString()
        .trim();

    final output = [
      if (t.output != null && t.output!.trim().isNotEmpty) t.output!.trim(),
      if (t.error != null && t.error!.trim().isNotEmpty) t.error!.trim(),
      if (t.output == null && t.error == null) ...t.progressLines,
    ].join('\n').trim();
    final lineCount = output.isEmpty ? 0 : output.split('\n').length;

    // ONE LINE, closed. A boxed two-line card per call is most of a phone
    // screen by the fourth one, and the agent's work is not the conversation —
    // it is punctuation inside it. Collapsed it reads as a line of activity to
    // skim past; the output stays one tap away for when it matters.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: lineCount == 0 ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: tint),
                  const SizedBox(width: 8),
                  Text(
                    t.tool,
                    style: AppTheme.mono(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          fontSize: 11.5,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (t.state == ToolCardState.running ||
                      t.state == ToolCardState.pending) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6, color: cs.primary),
                    ),
                  ],
                  if (lineCount > 0)
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (_open && output.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 2, 0, 8),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(9),
              ),
              // Horizontally scrollable: command output is full of long paths
              // and wrapping them makes a listing unreadable. The page itself
              // must never scroll sideways, so the overflow is confined here.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: looksLikeDiff(output)
                    ? DiffBody(output)
                    : SelectableText(
                        output,
                        style: AppTheme.mono(
                            fontSize: 11.5, height: 1.35, color: cs.onSurface),
                      ),
              ),
            ),
        ],
      ),
    );
  }


}
