import 'dart:convert';
import 'dart:io';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/core/analytics/analytics_repository.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/attachments_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/message_reactions_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/message_sources_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/sources_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/web_preview_screen.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/code_panel.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/fence_info.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/web_preview.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/tool_run_card.dart';
import 'package:cyberneurova_mobile/features/voice/presentation/widgets/message_speaker_button.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/authed_network_image.dart';

// ─── Message bubble ───────────────────────────────────────────────────────────

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.chatId,
    this.isLatest = false,
  });

  final MessageModel message;
  final String chatId;
  final bool isLatest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Failed-send placeholder gets its own dedicated UI — faded bubble
    // with the error text + a retry button. Renders on the assistant side.
    if (message.isError) {
      return _FailedBubble(
        message: message,
        chatId: chatId,
        ref: ref,
      );
    }

    final isUser = message.role == 'user';
    final cs = Theme.of(context).colorScheme;
    final text = message.content;

    // Variant A (design-lab) direction: assistant replies render as plain
    // text on the page background — no bubble, full available width; user
    // messages sit right-aligned in a soft rounded rect. Generous vertical
    // rhythm (~16 between turns).
    final bubble = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isUser && message.attachments.isNotEmpty)
            _UserAttachmentsStrip(attachments: message.attachments),
          if (text.isNotEmpty)
            isUser
                ? ConstrainedBox(
                    // ~85% of the available width so short replies read as
                    // chat turns, long ones still leave breathing room.
                    constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.sizeOf(context).width * 0.85),
                    child: GestureDetector(
                      onLongPress: () => _copy(context, text),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppTheme.radiusLg),
                            topRight: Radius.circular(AppTheme.radiusLg),
                            bottomLeft: Radius.circular(AppTheme.radiusLg),
                            // Subtle tail on the sender side.
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 16,
                              height: 1.4),
                        ),
                      ),
                    ),
                  )
                : GestureDetector(
                    onLongPress: () => _copy(context, text),
                    // While THIS reply is the one streaming, render it as plain
                    // text — no markdown parse, no code/math/tool segmentation.
                    // `_RichBody` re-segments and re-parses the whole growing
                    // string on every ~50ms flush (the segment cache misses
                    // because the text grew), and over thousands of chars that
                    // jams the UI thread on a real device: the reply "flushes",
                    // and the scroll gesture can't even be recognised. Plain
                    // Text is effectively free to lay out. The full markdown
                    // (code panels, math, selectable) renders once the stream
                    // settles and this stops being the streaming message.
                    child: (isLatest && ref.watch(streamRunningProvider))
                        ? _StreamingBody(text: text)
                        : _RichBody(
                            text: text,
                            chatId: chatId,
                            selectable: true,
                          ),
                  ),
          // Action row — only on assistant messages with content. Sits just
          // under the reply so it's discoverable without long-press. Copy
          // always; Regenerate only on the most recent assistant turn so we
          // don't let the user rewrite history mid-conversation.
          if (!isUser && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _MessageActions(
                chatId: chatId,
                messageId: message.id,
                text: text,
                showRetry: isLatest,
                // Continue is driven by chat-team's done.truncated flag
                // (inbox/014) which lives in truncatedMessagesProvider.
                // Precise — no false positives on legitimate code fences.
                ref: ref,
              ),
            ),
        ],
      ),
    );

    // Animate the latest message in; others render instantly
    if (isLatest) {
      return bubble
          .animate()
          .fadeIn(duration: 200.ms, curve: Curves.easeOut)
          .slideY(begin: 0.08, end: 0, duration: 200.ms,
              curve: Curves.easeOut);
    }
    return bubble;
  }
}

/// Tiny tap helper used by long-press AND the copy button below the bubble.
void _copy(BuildContext context, String text) {
  HapticFeedback.mediumImpact();
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Copied'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 1),
    ),
  );
}

/// Action row under each assistant message: Copy + (when latest) Regenerate
/// + thumbs up/down. Thumbs persist across rebuilds and relaunches via
/// SharedPreferences (see `message_reactions_provider.dart`). Not yet
/// synced to server — chat-team's /analytics/events is queued (#49).
class _MessageActions extends ConsumerWidget {
  const _MessageActions({
    required this.chatId,
    required this.messageId,
    required this.text,
    required this.showRetry,
    required this.ref,
  });

  final String chatId;
  final String messageId;
  final String text;
  final bool showRetry;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    // Watch reactions so when the user taps a thumb the icon updates
    // immediately AND persists across this build's lifetime.
    final reactions = ref.watch(messageReactionsProvider);
    final rating = reactions[messageId] ?? 0;

    // Continue is shown when chat-team's done.truncated flag fired for
    // this bubble. Disable while a stream is in flight so a double-tap
    // can't queue two simultaneous resumes.
    final streaming = ref.watch(streamRunningProvider);
    final truncated = ref
        .watch(truncatedMessagesProvider)
        .contains(messageId);

    // Web sources the server fetched for this answer — shown as a tappable
    // "Sources" chip to the right of the action icons (reference layout).
    final sources =
        ref.watch(messageSourcesProvider)[messageId] ?? const <String>[];

    final actions = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        if (truncated && !streaming) ...[
          _ContinuePill(
            onTap: () {
              HapticFeedback.mediumImpact();
              ref
                  .read(chatDetailProvider(chatId).notifier)
                  .resumeMessage(messageId);
            },
          ),
          const SizedBox(width: 4),
        ],
        _ActionIcon(
          icon: Icons.copy_rounded,
          tooltip: 'Copy',
          onTap: () => _copy(context, text),
        ),
        // Listen — feeds the message text to MisoTTS (Box A :8030) and
        // plays the returned WAV. State (idle/loading/playing) is
        // shared across all bubbles via [ttsPlaybackProvider] so only
        // one message speaks at a time.
        MessageSpeakerButton(
          messageId: messageId,
          text: text,
        ),
        if (showRetry)
          _ActionIcon(
            icon: Icons.refresh_rounded,
            tooltip: 'Regenerate',
            onTap: () {
              HapticFeedback.mediumImpact();
              final detail =
                  ref.read(chatDetailProvider(chatId)).valueOrNull;
              if (detail == null) return;
              MessageModel? prevUser;
              for (var i = detail.messages.length - 1; i >= 0; i--) {
                if (detail.messages[i].role == 'user') {
                  prevUser = detail.messages[i];
                  break;
                }
              }
              if (prevUser == null) return;
              ref
                  .read(chatDetailProvider(chatId).notifier)
                  .retry(prevUser.content);
            },
          ),
        _ActionIcon(
          icon: rating == 1
              ? Icons.thumb_up_rounded
              : Icons.thumb_up_outlined,
          tooltip: 'Good response',
          active: rating == 1,
          onTap: () {
            HapticFeedback.selectionClick();
            final next = rating == 1 ? 0 : 1;
            ref.read(messageReactionsProvider.notifier).set(messageId, next);
            if (next != 0) {
              ref.read(analyticsRepositoryProvider).track(
                    eventType: 'thumbs_up',
                    category: 'chat',
                    page: '/chat/$chatId',
                    metadata: {'messageId': messageId},
                  );
            }
          },
        ),
        _ActionIcon(
          icon: rating == -1
              ? Icons.thumb_down_rounded
              : Icons.thumb_down_outlined,
          tooltip: 'Poor response',
          active: rating == -1,
          onTap: () {
            HapticFeedback.selectionClick();
            final next = rating == -1 ? 0 : -1;
            ref.read(messageReactionsProvider.notifier).set(messageId, next);
            if (next != 0) {
              ref.read(analyticsRepositoryProvider).track(
                    eventType: 'thumbs_down',
                    category: 'chat',
                    page: '/chat/$chatId',
                    metadata: {'messageId': messageId},
                  );
            }
          },
        ),
      ],
    );

    if (sources.isEmpty) return actions;
    // Action icons on the left, a "Sources" chip on the right (the reference
    // layout). Expanded lets the icons wrap if the row gets tight.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: actions),
        const SizedBox(width: 8),
        _SourcesChip(sources: sources),
      ],
    );
  }
}

/// A compact "Sources" chip: overlapping source favicons + label, opening the
/// full citation sheet on tap (reference pattern). Sits to the right of the
/// action-icon row on answers the server web-searched.
class _SourcesChip extends StatelessWidget {
  const _SourcesChip({required this.sources});

  /// Source URLs, in the order the server fetched them.
  final List<String> sources;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      for (final u in sources) SourceItem(title: _host(u), url: u),
    ];
    final shown = items.take(3).toList();
    // Overlapping favicons: each 18px circle steps 11px so ~7px peeks out.
    final stackWidth = 18.0 + (shown.length - 1) * 11.0;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          showSourcesSheet(context, sources: items);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: stackWidth,
                height: 18,
                child: Stack(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * 11.0,
                        child: _Favicon(item: shown[i], ring: cs.surface),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'Sources',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _host(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}

/// One 18px favicon circle with a themed ring so overlapping ones stay
/// separable. Falls back to a globe glyph while loading or on error.
class _Favicon extends StatelessWidget {
  const _Favicon({required this.item, required this.ring});
  final SourceItem item;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget fallback() => Icon(Icons.public_rounded,
        size: 11, color: cs.onSurfaceVariant);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
        border: Border.all(color: ring, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: item.effectiveFavicon.isEmpty
          ? fallback()
          : CachedNetworkImage(
              imageUrl: item.effectiveFavicon,
              width: 15,
              height: 15,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback(),
              errorWidget: (_, __, ___) => fallback(),
            ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: 16,
        color: active ? cs.primary : cs.onSurfaceVariant,
      ),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      // 40×40 tap area (was 28) — closer to the 44pt min while staying
      // compact enough for the inline action row.
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}

/// Pill-styled "Continue" affordance shown when the latest assistant
/// message looks truncated (see [_looksTruncated]). More prominent than
/// a bare icon because the action is non-obvious — user wouldn't know
/// to long-press or tap a refresh icon to resume.
class _ContinuePill extends StatelessWidget {
  const _ContinuePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Light-mode legibility: cs.primary is ~2.8:1 on its own 0.12 tint in
    // the light palette — deepen the label/icon with onSurface ink (≈5:1).
    // Dark keeps the brand teal untouched.
    final ink = Theme.of(context).brightness == Brightness.light
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.35), cs.primary)
        : cs.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 14, color: ink),
            const SizedBox(width: 4),
            Text(
              'Continue',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline failure UI. Shown when the model returned no response or the
/// stream errored. Faded styling so it's visually distinct from a real
/// reply, with a Retry button that re-sends the original user text.
class _FailedBubble extends StatelessWidget {
  const _FailedBubble({
    required this.message,
    required this.chatId,
    required this.ref,
  });

  final MessageModel message;
  final String chatId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final retryText = message.retryText ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.35),
                border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusLg),
                  topRight: Radius.circular(AppTheme.radiusLg),
                  // Same shape language as the user rect, mirrored to the
                  // assistant side.
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(AppTheme.radiusLg),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 16, color: cs.error),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message.content,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // A run that ran out of turns gets Continue, not Retry.
                  //
                  // Retrying spends the same budget arriving at the same place,
                  // and throws away what the run already did — files written,
                  // packages installed. Continuing keeps it.
                  if (message.content.startsWith(kStepLimitReason)) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(chatDetailProvider(chatId).notifier)
                            .continueRun();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                size: 16, color: cs.error),
                            const SizedBox(width: 4),
                            Text(
                              'Continue',
                              style: TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (retryText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(chatDetailProvider(chatId).notifier)
                            .retry(retryText);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                size: 16, color: cs.error),
                            const SizedBox(width: 4),
                            Text(
                              'Retry',
                              style: TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders assistant text: splits out long fenced code blocks (≥6 lines) into
/// a glowing `CodeTeaser` that opens the full code in a bottom sheet. Inline
/// short snippets stay in the markdown.
// Sahachiel: cache parsed segments by text so static bubbles don't re-run the
// two regex passes on every parent rebuild (the per-token streaming storm
// rebuilds the whole message list).
/// Plain-text render of the in-flight streaming reply.
///
/// Deliberately dumb: a single [Text] with the same paragraph metrics the
/// markdown body uses, so when the stream settles and [_RichBody] takes over
/// the swap is barely perceptible. No markdown parse, no segmentation, no
/// selection tree — the whole point is that laying this out 20×/s over a
/// growing string stays cheap enough that the UI thread keeps servicing
/// scroll and touch. Raw markdown syntax (**, ##, ```) shows briefly during
/// the stream, then formats on completion — the accepted trade for a reply
/// that streams smoothly and stays scrollable.
class _StreamingBody extends StatelessWidget {
  const _StreamingBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.55),
    );
  }
}

final _segmentsCache = <String, List<_Segment>>{};

class _RichBody extends ConsumerWidget {
  const _RichBody({
    required this.text,
    required this.chatId,
    this.selectable = true,
  });
  final String text;

  /// Which session a saved code block belongs to.
  final String chatId;

  /// False while this bubble is actively streaming — see the call site.
  final bool selectable;

  // The info string is everything after the opening fence, not just a bare
  // language. Models routinely write ```html:clock.html or ```py title=x.py,
  // and the old `[a-zA-Z0-9_+\-]+` could not match a dot or a colon — so the
  // fence did not match AT ALL and the whole block fell through to markdown as
  // raw text. The one case where the model tells us what the file should be
  // called was the one case we could not read.
  static final _fenceRe = RegExp(r'```([^\n`]*)\n([\s\S]*?)```');
  // Match $$...$$ block LaTeX. We restrict to single-paragraph blocks
  // (no blank-line-between) — keeps the regex non-greedy + safe.
  static final _mathRe = RegExp(r'\$\$([^\$]+?)\$\$');
  // chat-team inbox/020: assistant messages with an inline-generated image
  // carry a `[GENERATED_IMAGE:/api/images/<uuid>/view]` marker in the body.
  // Strip the marker out of the displayed text and render the image. The
  // URL is host-relative; resolveImageUrl + AuthedNetworkImage (which sends
  // the Bearer header only to our own origin) handle the rest.
  static final _generatedImageRe =
      RegExp(r'\[GENERATED_IMAGE:([^\]]+)\]');
  // Agentic tool-run marker: `[TOOL_RUN:{json}]` (inbox/025). The naive
  // non-greedy regex `\[TOOL_RUN:(\{[\s\S]*?\})\]` under-matches, because
  // the JSON object nests braces (`{"steps":[{...}]}` — the first `}]` in
  // the text closes the *last step + steps array*, not the marker). So we
  // locate the marker start textually, then try each successive `}]`
  // candidate end and let `jsonDecode` arbitrate: the first candidate that
  // decodes is the marker payload. Braces/`}]` inside JSON string values
  // (diff content) are handled for free — those candidates fail to decode
  // (unterminated string) and the scan continues.
  // Known limitation: a syntactically invalid payload never decodes, so
  // the marker is swallowed to the first `}]` (or end of segment while it
  // is still streaming in) and renders nothing — never raw JSON.
  static const _toolRunPrefix = '[TOOL_RUN:';
  static const _toolRunMarkerStart = '[TOOL_RUN:{';

  /// Tries to parse a `[TOOL_RUN:{...}]` payload starting at [jsonStart]
  /// (index of the `{`). Returns the parsed run (null when the JSON is
  /// valid but carries no usable steps) plus the index just past the
  /// closing `]`; returns null when no candidate end decodes.
  static ({ToolRun? run, int end})? _tryParseToolRun(
      String text, int jsonStart) {
    var p = text.indexOf('}]', jsonStart);
    while (p >= 0) {
      final candidate = text.substring(jsonStart, p + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return (run: ToolRun.fromJson(decoded), end: p + 2);
        }
        return null;
      } catch (_) {
        p = text.indexOf('}]', p + 1);
      }
    }
    return null;
  }

  /// Split the message into ordered segments: markdown, big code blocks
  /// (rendered via CodeTeaser), and LaTeX math blocks. We process the
  /// outer code fences first (mermaid + everything else), then re-scan
  /// markdown segments for $$..$$ math blocks.
  List<_Segment> _segments() {
    final cached = _segmentsCache[text];
    if (cached != null) return cached;
    // Pass 1: code fences (and identify mermaid as a special code subtype).
    final intermediate = <_Segment>[];
    var cursor = 0;
    for (final m in _fenceRe.allMatches(text)) {
      final before = text.substring(cursor, m.start);
      if (before.isNotEmpty) intermediate.add(_Segment.markdown(before));
      final info = FenceInfo.parse(m.group(1));
      final lang = info.language;
      // The newline before the closing fence belongs to the MARKDOWN, not to
      // the code. Keeping it made every block one line longer than it is:
      // `a\nb\n` counted as three, so the six-line rule below actually
      // fired at five and a five-line snippet became a full teaser card
      // instead of staying inline. It also made the teaser footer offer
      // "Show all 17 lines" for sixteen lines of code plus a blank one.
      //
      // Stripped here rather than in CodeTeaser so the count, the preview
      // and the full-screen panel all see the same thing.
      final code = (m.group(2) ?? '').replaceFirst(RegExp(r'\n[ \t]*$'), '');
      final lineCount = '\n'.allMatches(code).length + 1;
      // Mermaid always opens via CodeTeaser so the user can see + copy the
      // diagram source. True mermaid SVG rendering needs a WebView; deferred.
      //
      // A fence that NAMES a file is always a teaser regardless of length: the
      // model saying "this is clock.html" is exactly the signal that the block
      // is meant to become a file, and the six-line threshold would deny a
      // four-line config or script the one action that matters.
      if (lang == 'mermaid' || lineCount >= 6 || info.filename != null) {
        intermediate.add(_Segment.bigCode(
            code: code, language: lang, filename: info.filename));
      } else {
        intermediate.add(_Segment.markdown(m.group(0) ?? ''));
      }
      cursor = m.end;
    }
    if (cursor < text.length) intermediate.add(_Segment.markdown(text.substring(cursor)));

    // Pass 2: split markdown segments around $$ math blocks.
    final afterMath = <_Segment>[];
    for (final s in intermediate) {
      if (s.isCode) {
        afterMath.add(s);
        continue;
      }
      var c = 0;
      for (final m in _mathRe.allMatches(s.text)) {
        final pre = s.text.substring(c, m.start);
        if (pre.isNotEmpty) afterMath.add(_Segment.markdown(pre));
        afterMath.add(_Segment.math(m.group(1)?.trim() ?? ''));
        c = m.end;
      }
      if (c < s.text.length) {
        afterMath.add(_Segment.markdown(s.text.substring(c)));
      }
    }

    // Pass 3: split markdown segments around [GENERATED_IMAGE:url] markers
    // (chat-team inbox/020). The URL is host-relative; resolveImageUrl on
    // the render side prepends webOrigin. The marker text never reaches
    // the markdown body — we slice it out and put a real image segment
    // in its place.
    final withImages = <_Segment>[];
    for (final s in afterMath) {
      if (s.isCode || s.isMath) {
        withImages.add(s);
        continue;
      }
      var c = 0;
      for (final m in _generatedImageRe.allMatches(s.text)) {
        final pre = s.text.substring(c, m.start);
        if (pre.trim().isNotEmpty) withImages.add(_Segment.markdown(pre));
        final url = (m.group(1) ?? '').trim();
        if (url.isNotEmpty) withImages.add(_Segment.generatedImage(url));
        c = m.end;
      }
      if (c < s.text.length) {
        final tail = s.text.substring(c);
        if (tail.trim().isNotEmpty) withImages.add(_Segment.markdown(tail));
      }
    }

    // Pass 4: split markdown segments around [TOOL_RUN:{json}] markers
    // (inbox/025 agentic runs). Same shape as the generated-image pass —
    // the marker text never reaches the markdown body; a validated marker
    // becomes a ToolRunCard segment, an unparseable one renders nothing.
    final out = <_Segment>[];
    for (final s in withImages) {
      if (s.isCode || s.isMath || s.isGeneratedImage) {
        out.add(s);
        continue;
      }
      var c = 0;
      while (true) {
        final idx = s.text.indexOf(_toolRunMarkerStart, c);
        if (idx < 0) break;
        final pre = s.text.substring(c, idx);
        if (pre.trim().isNotEmpty) out.add(_Segment.markdown(pre));
        final parsed =
            _tryParseToolRun(s.text, idx + _toolRunPrefix.length);
        if (parsed == null) {
          // Malformed or still-streaming marker — swallow to the first
          // `}]` (or end of segment) instead of showing raw JSON.
          final bail = s.text.indexOf('}]', idx);
          c = bail < 0 ? s.text.length : bail + 2;
        } else {
          if (parsed.run != null) out.add(_Segment.toolRun(parsed.run!));
          c = parsed.end;
        }
      }
      if (c < s.text.length) {
        final tail = s.text.substring(c);
        if (tail.trim().isNotEmpty) out.add(_Segment.markdown(tail));
      }
    }

    // Bound the cache; the transient per-token streaming texts get evicted in
    // bulk when it grows large, while completed bubbles stay cached.
    if (_segmentsCache.length > 128) _segmentsCache.clear();
    _segmentsCache[text] = out;
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final segments = _segments();
    // Only where there is somewhere to save TO. A chat with no device session
    // has no working directory, and a Save button that cannot save is the same
    // mistake as a Run button that cannot run.
    final workspace = ref.watch(shellWorkspaceProvider(chatId));

    // Build the markdown stylesheet once per build (not once per segment).
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.55),
      code: TextStyle(
        fontSize: 13,
        // Light: the near-invisible 0.25 chip (light outline on a light
        // page) gets a bump so inline code still reads as a chip.
        backgroundColor: cs.outline.withValues(alpha: isLight ? 0.45 : 0.25),
        // Dark: brand-adjacent pale mint, ~10.5:1 on the navy chip.
        // Light: raw cs.primary (#0E9C86) is only ~2.8:1 on the light chip,
        // so deepen it with onSurface ink — lands ~5:1 (AA for 13px code)
        // while staying in the brand-teal hue and token-derived.
        color: isLight
            ? Color.alphaBlend(
                cs.onSurface.withValues(alpha: 0.35), cs.primary)
            : const Color(0xFF7EDCB4),
      ),
      codeblockDecoration: BoxDecoration(
        // Same per-brightness bump as the inline chip — 0.15 of the light
        // outline over the light page is invisible.
        color: cs.outline.withValues(alpha: isLight ? 0.35 : 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      // flutter_markdown's default blockquote is a bright light-blue slab —
      // unreadable in dark mode. Left accent rule + muted text instead.
      // Note: no borderRadius here — Flutter forbids borderRadius with a
      // non-uniform (left-only) border and throws at paint time.
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.5),
        border: Border(
          left: BorderSide(color: cs.primary.withValues(alpha: 0.6), width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      blockquote: TextStyle(
        fontSize: 15,
        color: cs.onSurfaceVariant,
        height: 1.55,
      ),
    );
    Widget md(String src) =>
        MarkdownBody(data: src, selectable: selectable, styleSheet: sheet);

    // Whether anything in THIS reply is a runnable web page. Computed over the
    // whole message rather than per block, because the HTML almost always
    // arrives with its CSS and JS in separate fences and running the HTML
    // alone would show an unstyled, inert page.
    final codeBlocks = <CodeBlock>[
      for (final s in segments)
        if (s.isCode) (language: s.language, code: s.code!),
    ];
    final preview = assembleWebPreview(codeBlocks);

    // Which segment carries the Run button, by identity rather than by a
    // counter incremented during build: segments are cached per message, so
    // identity is stable, whereas a counter would double-count the moment one
    // block rebuilt on its own and move the button to the wrong fence.
    final anchor = preview == null
        ? null
        : segments.where((s) => s.isCode).elementAt(preview.anchorIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in segments)
          if (s.isCode)
            CodeTeaser(
              code: s.code!,
              language: s.language,
              filename: s.filename,
              onRun: identical(s, anchor)
                  ? () => showWebPreview(context, preview!)
                  : null,
              onSave: workspace == null
                  ? null
                  : (suggested) => _saveBlock(
                        context,
                        workspace: workspace,
                        suggested: suggested,
                        code: s.code!,
                      ),
            )
          else if (s.isMath)
            _MathBlock(latex: s.math!)
          else if (s.isGeneratedImage)
            _GeneratedImageBlock(rawUrl: s.generatedImageUrl!)
          else if (s.isToolRun)
            // Full width; the card carries its own 8px vertical margin.
            SizedBox(
              width: double.infinity,
              child: ToolRunCard(run: s.toolRun!),
            )
          else
            md(s.text),
      ],
    );
  }
}

/// Strip of attachment thumbnails shown above the user's text bubble.
/// Prefers a local file when we still have one on disk (the user just
/// picked this image — no network needed); falls back to authed network
/// fetch for older messages reloaded from history. Non-image attachments
/// show as a labelled chip. Tap an image to open it full-screen.
class _UserAttachmentsStrip extends ConsumerWidget {
  const _UserAttachmentsStrip({required this.attachments});
  final List<MessageAttachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final localPaths = ref.watch(localAttachmentPathsProvider);
    final imageAttachments =
        attachments.where((a) => a.contentType.startsWith('image/')).toList();
    final fileAttachments =
        attachments.where((a) => !a.contentType.startsWith('image/')).toList();

    Widget renderImage(MessageAttachment a) {
      final localPath = localPaths[a.url];
      if (localPath != null && File(localPath).existsSync()) {
        return Image.file(File(localPath), fit: BoxFit.cover);
      }
      return AuthedNetworkImage(
        imageUrl: ApiConstants.resolveImageUrl(a.url),
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: 80,
          height: 80,
          color: cs.surfaceContainer,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined,
              color: cs.onSurfaceVariant),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (imageAttachments.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in imageAttachments)
                  GestureDetector(
                    onTap: () => _openFullscreen(context, a, localPaths[a.url]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 200,
                          maxHeight: 200,
                          minWidth: 80,
                          minHeight: 80,
                        ),
                        child: renderImage(a),
                      ),
                    ),
                  ),
              ],
            ),
          if (fileAttachments.isNotEmpty) ...[
            if (imageAttachments.isNotEmpty) const SizedBox(height: 6),
            for (final a in fileAttachments)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        a.name ?? 'attachment',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _openFullscreen(
          BuildContext context, MessageAttachment a, String? localPath) =>
      showImageFullscreen(context, url: a.url, localPath: localPath);
}

/// Full-screen, pinch-zoomable image viewer used by every image surface
/// (pending attachment chips, sent attachments, generated images). Renders the
/// local file when available, else the Bearer-authed remote image.
void showImageFullscreen(BuildContext context,
    {required String url, String? localPath}) {
  final useLocal = localPath != null && File(localPath).existsSync();
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: useLocal
                ? Image.file(File(localPath), fit: BoxFit.contain)
                : AuthedNetworkImage(
                    imageUrl: ApiConstants.resolveImageUrl(url),
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
    ),
  );
}

class _GeneratedImageBlock extends StatelessWidget {
  const _GeneratedImageBlock({required this.rawUrl});
  final String rawUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = ApiConstants.resolveImageUrl(rawUrl);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => showImageFullscreen(context, url: rawUrl),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: AuthedNetworkImage(
            imageUrl: resolved,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              color: cs.surfaceContainer,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined,
                      size: 32, color: cs.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(
                    "Couldn't load generated image",
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Turns a printed code block into a real file in the session directory.
///
/// The name is confirmed rather than assumed: the fence's own name is right
/// far more often than not, but "save the wrong file silently" is the failure
/// this whole feature exists to correct.
Future<void> _saveBlock(
  BuildContext context, {
  required ShellWorkspace workspace,
  required String suggested,
  required String code,
}) async {
  final controller = TextEditingController(text: suggested);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Save to this session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'File name',
              isDense: true,
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          const SizedBox(height: 10),
          Text(
            workspace.active.shell.cwd,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.trim().isEmpty || !context.mounted) return;

  try {
    final path = workspace.saveFile(name.trim(), code);
    if (!context.mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to $path'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Couldn't save. "
            '${userMessageFor(context, e)}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Segment {
  const _Segment._({
    this.text = '',
    this.code,
    this.language,
    this.filename,
    this.math,
    this.generatedImageUrl,
    this.toolRun,
  });
  factory _Segment.markdown(String t) => _Segment._(text: t);
  factory _Segment.bigCode(
          {required String code, String? language, String? filename}) =>
      _Segment._(code: code, language: language, filename: filename);
  factory _Segment.math(String latex) => _Segment._(math: latex);
  factory _Segment.generatedImage(String url) =>
      _Segment._(generatedImageUrl: url);
  factory _Segment.toolRun(ToolRun run) => _Segment._(toolRun: run);

  final String text;
  final String? code;
  final String? language;

  /// What the model called this block, when the fence said so.
  final String? filename;
  final String? math;
  final String? generatedImageUrl;
  final ToolRun? toolRun;

  bool get isCode => code != null;
  bool get isMath => math != null;
  bool get isGeneratedImage => generatedImageUrl != null;
  bool get isToolRun => toolRun != null;
}

/// Renders a `$$..$$` LaTeX block via flutter_math_fork. Falls back to a
/// monospace text rendering of the raw LaTeX when the parser can't handle
/// the expression — so the user never sees a blank space where there
/// should be math.
class _MathBlock extends StatelessWidget {
  const _MathBlock({required this.latex});
  final String latex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Math.tex(
          latex,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(fontSize: 16, color: cs.onSurface),
          onErrorFallback: (err) => Text(
            latex,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
