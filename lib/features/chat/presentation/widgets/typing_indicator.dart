import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

/// Typing indicator that morphs label as time passes + reacts to
/// auto-web-search and agentic tool status events from the stream. Priority:
///   1. activeToolStatusProvider != null → live tool line ("Reading
///      main.py…") with a small spinner (inbox/025)
///   2. activeWebSearchProvider != null → "Searching the web: <query>" /
///      "Web results (N)" / "No web results — answering from training"
///   3. _showLabel true after 1.2s of waiting → "Thinking…"
///   4. Just the three bouncing dots
class TypingIndicator extends ConsumerStatefulWidget {
  const TypingIndicator({super.key});

  @override
  ConsumerState<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends ConsumerState<TypingIndicator> {
  bool _showLabel = false;
  Timer? _labelTimer;

  @override
  void initState() {
    super.initState();
    _labelTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showLabel = true);
    });
  }

  @override
  void dispose() {
    _labelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final search = ref.watch(activeWebSearchProvider);
    final tool = ref.watch(activeToolStatusProvider);
    // Compose the inline label. Live tool status wins (it's the most
    // current signal), then web-search status; falls through to
    // "Thinking" after 1.2s; otherwise dots only.
    String? label;
    IconData? labelIcon;
    var showSpinner = false;
    if (tool != null) {
      final q = tool.query;
      label = (q != null && q.isNotEmpty) ? '$q…' : 'Working…';
      showSpinner = true;
    } else if (search != null) {
      switch (search.phase) {
        case 'searching':
          label = search.query != null && search.query!.isNotEmpty
              ? 'Searching: ${search.query}'
              : 'Searching the web…';
          labelIcon = Icons.travel_explore_rounded;
        case 'searched':
          label = search.resultCount != null
              ? 'Web results · ${search.resultCount}'
              : 'Web results';
          labelIcon = Icons.public_rounded;
        case 'no-results':
          label = 'No web results — answering';
          labelIcon = Icons.travel_explore_outlined;
      }
    } else if (_showLabel) {
      label = 'Thinking';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primary.withValues(alpha: 0.15),
            child:
                Icon(Icons.auto_awesome_rounded, size: 14, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null) ...[
                  if (showSpinner) ...[
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (labelIcon != null) ...[
                    Icon(labelIcon, size: 14, color: cs.primary)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fade(duration: 600.ms, begin: 0.5, end: 1.0),
                    const SizedBox(width: 6),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontStyle: (tool != null || search != null)
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ).animate().fadeIn(duration: 200.ms),
                  ),
                  const SizedBox(width: 6),
                ],
                ...List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(
                        onPlay: (c) => c.repeat(),
                        delay: Duration(milliseconds: i * 160))
                    .scaleXY(
                        begin: 0.6,
                        end: 1.0,
                        duration: 400.ms,
                        curve: Curves.easeInOut)
                    .then()
                    .scaleXY(begin: 1.0, end: 0.6, duration: 400.ms,
                        curve: Curves.easeInOut),
              ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
