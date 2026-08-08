// lib/features/voice/presentation/widgets/message_speaker_button.dart
//
// Speaker / "Listen" button rendered in the assistant-message action
// row. Three visual states driven by [ttsPlaybackProvider]:
//
//   idle      → outlined speaker icon
//   loading   → small spinner (waiting for /tts response)
//   playing   → filled stop-icon (tap to stop)
//
// Designed to match the existing _ActionIcon visual rhythm in
// chat_detail_screen — same size, same color tokens, same haptic
// feedback. No extra padding/shadows, just a single icon button with
// an AnimatedSwitcher between states so the change is smooth.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/features/voice/presentation/providers/tts_playback_provider.dart';

class MessageSpeakerButton extends ConsumerWidget {
  const MessageSpeakerButton({
    super.key,
    required this.messageId,
    required this.text,
  });

  final String messageId;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(ttsPlaybackProvider);
    final isActive = playback.activeMessageId == messageId;

    final status = isActive ? playback.status : TtsPlaybackStatus.idle;

    Widget child;
    switch (status) {
      case TtsPlaybackStatus.idle:
        child = Icon(
          Icons.volume_up_outlined,
          key: const ValueKey('idle'),
          size: 18,
          color: cs.onSurfaceVariant,
        );
        break;
      case TtsPlaybackStatus.loading:
        child = SizedBox(
          key: const ValueKey('loading'),
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.primary,
          ),
        );
        break;
      case TtsPlaybackStatus.playing:
        child = Icon(
          Icons.stop_circle_rounded,
          key: const ValueKey('playing'),
          size: 20,
          color: cs.primary,
        );
        break;
    }

    return Tooltip(
      message: status == TtsPlaybackStatus.playing ? 'Stop' : 'Listen',
      child: InkResponse(
        onTap: () {
          if (text.trim().isEmpty) return;
          HapticFeedback.selectionClick();
          ref.read(ttsPlaybackProvider.notifier).toggle(
                messageId: messageId,
                text: text,
              );
        },
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: child,
          ),
        ),
      ),
    );
  }
}
