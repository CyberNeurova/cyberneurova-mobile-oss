// lib/features/voice/presentation/providers/tts_playback_provider.dart
//
// TTS playback state. One global player; per-message status so the UI
// can show the right icon on the active bubble (spinner while loading,
// stop icon while playing, speaker icon idle).
//
// Caching: WAV bytes are cached on disk by messageId for the lifetime
// of the session. Re-tapping a message replays without re-billing the
// server. Cache is cleared when the player is disposed (app close).

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';
import 'package:cyberneurova_mobile/features/voice/data/repositories/voice_repository.dart';

enum TtsPlaybackStatus { idle, loading, playing }

class TtsPlaybackState {
  const TtsPlaybackState({
    this.activeMessageId,
    this.status = TtsPlaybackStatus.idle,
    this.error,
  });

  /// The message currently loading or playing. `null` when nothing is
  /// active — speaker buttons show idle icon.
  final String? activeMessageId;
  final TtsPlaybackStatus status;
  final String? error;

  TtsPlaybackState copyWith({
    String? activeMessageId,
    TtsPlaybackStatus? status,
    String? error,
    bool clearActive = false,
    bool clearError = false,
  }) =>
      TtsPlaybackState(
        activeMessageId:
            clearActive ? null : (activeMessageId ?? this.activeMessageId),
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
      );
}

final ttsPlaybackProvider =
    NotifierProvider<TtsPlaybackNotifier, TtsPlaybackState>(
  TtsPlaybackNotifier.new,
);

class TtsPlaybackNotifier extends Notifier<TtsPlaybackState> {
  late final AudioPlayer _player;
  // messageId → on-disk WAV file path. Survives only for the session
  // (temp dir, cleared on app close). Trades memory for repeat-tap
  // speed and zero re-billing.
  final Map<String, String> _cache = {};
  StreamSubscription<PlayerState>? _stateSub;

  @override
  TtsPlaybackState build() {
    _player = AudioPlayer();
    _stateSub = _player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed) {
        state = state.copyWith(
          status: TtsPlaybackStatus.idle,
          clearActive: true,
        );
      }
    });
    ref.onDispose(() async {
      await _stateSub?.cancel();
      await _player.dispose();
    });
    return const TtsPlaybackState();
  }

  /// Toggle: if this message is currently playing, stop. Otherwise
  /// load and play it (using cached bytes if we've heard it before).
  Future<void> toggle({
    required String messageId,
    required String text,
  }) async {
    // Tapping the bubble that is already loading OR playing → stop.
    //
    // `loading` used to fall through to the fetch below, and the cache is
    // only written when the first fetch RETURNS — so an impatient second tap
    // during the wait issued a second /tts POST for the same message. That is
    // a real synthesis on the GPU and a second charge against media credits,
    // against a file that promises re-tapping replays without re-billing.
    if (state.activeMessageId == messageId &&
        state.status != TtsPlaybackStatus.idle) {
      await _player.stop();
      state = state.copyWith(
        status: TtsPlaybackStatus.idle,
        clearActive: true,
      );
      return;
    }

    // If something else is playing → stop it first so two bubbles
    // can't speak over each other.
    if (state.status != TtsPlaybackStatus.idle) {
      await _player.stop();
    }

    state = TtsPlaybackState(
      activeMessageId: messageId,
      status: TtsPlaybackStatus.loading,
    );

    try {
      final cached = _cache[messageId];
      final path = cached ?? await _fetchAndCache(messageId, text);
      // Whoever we were fetching for may no longer be who is active: the
      // fetch takes seconds, and the user can tap a different bubble or stop
      // this one meanwhile. Without this check the finishing request wrote
      // `copyWith(status: playing)` onto whatever state it found — and
      // copyWith KEEPS activeMessageId — so an older message's audio played
      // while a newer bubble showed the stop icon, and stopping that bubble
      // stopped audio it never started.
      if (state.activeMessageId != messageId) return;
      await _player.setFilePath(path);
      if (state.activeMessageId != messageId) return;
      // Set state BEFORE play() so the UI updates instantly; the
      // playerStateStream subscriber resets to idle on completion.
      state = state.copyWith(status: TtsPlaybackStatus.playing);
      await _player.play();
    } catch (e) {
      // Free-tier hits 403 TIER_REQUIRED — surface the paywall instead
      // of a bare error string. Other errors (502 UPSTREAM_FAILED,
      // network, etc.) just clear loading and let the UI fall back.
      if (e is ForbiddenException && e.code == 'TIER_REQUIRED') {
        // The paywall fires either way — the user tapped Listen and is gated,
        // whichever message they are on now. Only the STATE write is
        // ownership-checked, and it needs to be: this branch wrote a blank
        // state unconditionally, so a 403 landing late cleared whatever
        // bubble had since become active, taking its spinner with it.
        //
        // My own asymmetry, added in the same commit that put the check on
        // the branch below. Two writes in one catch, only one of them guarded.
        if (state.activeMessageId == messageId) {
          state = const TtsPlaybackState(status: TtsPlaybackStatus.idle);
        }
        ref.read(pendingPaywallTriggerProvider.notifier).state =
            const PaywallTrigger(reason: PaywallReason.voiceListen);
        return;
      }
      // Same ownership rule as the success path: a request that fails after
      // the user moved on must not drag the bubble they are now waiting on
      // back to idle.
      if (state.activeMessageId != messageId) return;
      state = TtsPlaybackState(
        activeMessageId: messageId,
        status: TtsPlaybackStatus.idle,
        error: e.toString(),
      );
    }
  }

  /// Stop playback regardless of which message is active.
  Future<void> stop() async {
    if (state.status == TtsPlaybackStatus.idle) return;
    await _player.stop();
    state = state.copyWith(
      status: TtsPlaybackStatus.idle,
      clearActive: true,
    );
  }

  Future<String> _fetchAndCache(String messageId, String text) async {
    final wav = await ref.read(voiceRepositoryProvider).synthesize(text);
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/tts_$messageId.wav');
    await file.writeAsBytes(wav, flush: true);
    _cache[messageId] = file.path;
    return file.path;
  }
}
