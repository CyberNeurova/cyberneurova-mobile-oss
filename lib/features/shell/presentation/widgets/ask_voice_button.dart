import 'dart:async';
import 'dart:io';

import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:cyberneurova_mobile/features/voice/data/repositories/voice_repository.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';

/// Dictation for the Ask bar.
///
/// ## Why not the chat composer's control
///
/// That one is press-and-hold with a live waveform, drag-up-to-lock and
/// drag-left-to-cancel — about two hundred lines of gesture state. It earns
/// that in a chat, where voice is a first-class way to send a whole message.
///
/// Here it is dictation into an existing field, on a screen whose bottom half
/// is a terminal. Tap to start, tap to stop is the whole interaction: a
/// press-and-hold in a cramped bar next to a Send button is a good way to send
/// a half-recorded message by accident, and a waveform would take the space
/// the terminal is using.
///
/// ## Why voice at all on this surface
///
/// Because the prompts here are long and the keyboard is not. "Find every
/// config file under src that mentions the old API host and tell me which ones
/// still matter" is thirty seconds of speech and a minute of thumb-typing on a
/// phone — and the phone is the whole computer.
class AskVoiceButton extends ConsumerStatefulWidget {
  const AskVoiceButton({super.key, required this.onTranscribed});

  /// Receives the transcript. The caller decides where it goes — appended to
  /// whatever is already typed, not replacing it.
  final void Function(String text) onTranscribed;

  @override
  ConsumerState<AskVoiceButton> createState() => _AskVoiceButtonState();
}

class _AskVoiceButtonState extends ConsumerState<AskVoiceButton> {
  final _recorder = AudioRecorder();

  bool _recording = false;
  bool _transcribing = false;
  String? _path;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  /// Long enough for a real instruction, short enough that a pocket recording
  /// cannot run until the battery dies.
  static const _maxLength = Duration(minutes: 5);

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_recording || _transcribing) return;

    if (!await _recorder.hasPermission()) {
      _say('Microphone permission is off for this app.');
      return;
    }

    HapticFeedback.mediumImpact();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ask_${DateTime.now().millisecondsSinceEpoch}.wav';

    // WAV/PCM, matching the chat composer: the AAC path goes through
    // MediaRecorder, which reports no amplitude on Samsung hardware. 16 kHz
    // mono is ~1.9 MB/min, so even the cap stays well under the upload limit.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    if (!mounted) return;
    setState(() {
      _recording = true;
      _path = path;
      _elapsed = Duration.zero;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= _maxLength) _stop();
    });
  }

  Future<void> _stop({bool discard = false}) async {
    if (!_recording) return;
    _ticker?.cancel();
    _ticker = null;

    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);

    final file = path ?? _path;
    if (discard || file == null) {
      _deleteQuietly(file);
      return;
    }

    // A stray tap has nothing in it, and sending it to be transcribed just
    // costs the user a round trip to be told nothing was said.
    if (_elapsed.inMilliseconds < 600) {
      _deleteQuietly(file);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _transcribing = true);
    try {
      final text = await ref.read(voiceRepositoryProvider).transcribe(file);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        _say('Nothing was picked up.');
      } else {
        widget.onTranscribed(text.trim());
      }
    } catch (e) {
      if (!mounted) return;
      // Spoken aloud. The app was reading Dart exceptions to people.
      _say('Could not transcribe that. ${userMessageFor(context, e)}');
    } finally {
      // The clip is ours and temporary. Leaving WAVs in the cache directory is
      // how an app quietly eats a gigabyte of someone's storage.
      _deleteQuietly(file);
      if (mounted) setState(() => _transcribing = false);
    }
  }

  void _deleteQuietly(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Best effort. A leftover temp file is not worth an error to the user.
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_transcribing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_recording) {
      // While recording the control becomes two: stop-and-use, and discard.
      // Without an explicit discard the only way out of a mis-tap is to record
      // silence and wait for a transcript of nothing.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Discard',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 19, color: cs.error),
            onPressed: () => _stop(discard: true),
          ),
          Text(
            _mmss(_elapsed),
            style: AppTheme.mono(
              fontSize: 12,
              color: cs.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Stop and transcribe',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.stop_circle_rounded, size: 22, color: cs.error),
            onPressed: _stop,
          ),
        ],
      );
    }

    return IconButton(
      tooltip: 'Dictate',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(Icons.mic_none_rounded, size: 20, color: cs.onSurfaceVariant),
      onPressed: _start,
    );
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
