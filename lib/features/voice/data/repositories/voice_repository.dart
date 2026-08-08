import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';

final voiceRepositoryProvider = Provider<VoiceRepository>((ref) {
  return VoiceRepository(ref.watch(apiClientProvider));
});

class VoiceRepository {
  VoiceRepository(this._client);
  final ApiClient _client;

  /// Upload a recorded audio file → faster-whisper-large-v3 on Box A
  /// :8032 → returns the transcribed text.
  ///
  /// Response shape (server-side route at
  /// app/api/mobile/v1/voice/transcribe/route.ts):
  ///   { success, text, language, language_probability, duration, segments }
  ///
  /// Throws an [AppException] (mapped by ErrorInterceptor) on:
  ///   - 403 TIER_REQUIRED        — free tier, surfaces as the
  ///                                 standard upgrade-paywall
  ///   - 413 PAYLOAD_TOO_LARGE    — >50 MB audio
  ///   - 502 UPSTREAM_FAILED      — Whisper unreachable
  ///   - 503 STT_UNAVAILABLE      — STT_BASE_URL missing
  Future<String> transcribe(String audioFilePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(audioFilePath),
    });
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.VOICE_TRANSCRIBE,
      data: formData,
    );
    // Server returns "text" (not the legacy "transcript" name we used to
    // accept). Fall back to "transcript" for one release cycle so any
    // ahead-of-version build doesn't crash.
    final body = res.data ?? {};
    return (body['text'] as String?) ??
        (body['transcript'] as String?) ??
        '';
  }

  /// Synthesize speech from text via MisoTTS 8B on Box A :8030.
  /// Returns raw WAV bytes (~24 kHz mono 16-bit PCM). Caller is
  /// responsible for caching + playback (see [voiceTtsPlaybackProvider]).
  ///
  /// Response: audio/wav body, NOT JSON. We use Dio's bytes ResponseType
  /// to skip the JSON parser and get a Uint8List directly.
  ///
  /// Throws an [AppException] (mapped by ErrorInterceptor) on:
  ///   - 403 TIER_REQUIRED        — free tier, surfaces as paywall
  ///   - 502 UPSTREAM_FAILED      — MisoTTS unreachable
  ///   - 503 TTS_UNAVAILABLE      — TTS_BASE_URL missing
  Future<Uint8List> synthesize(
    String text, {
    int speaker = 0,
    int maxAudioLengthMs = 30000,
  }) async {
    final res = await _client.post<List<int>>(
      ApiConstants.TTS,
      data: {
        'text': text,
        'speaker': speaker,
        'max_audio_length_ms': maxAudioLengthMs,
      },
      options: Options(
        responseType: ResponseType.bytes,
        // Body is JSON in, bytes out — set Content-Type explicitly so
        // Dio doesn't override based on responseType.
        headers: {'Content-Type': 'application/json'},
      ),
    );
    return Uint8List.fromList(res.data!);
  }

  /// Returns the voice WebSocket ticket for full voice chat.
  Future<({String wsUrl, String ticket, int expiresIn})> getVoiceAuth() async {
    final res = await _client.post<Map<String, dynamic>>(
      ApiConstants.VOICE_AUTH,
    );
    return (
      wsUrl: res.data!['wsUrl'] is String ? res.data!['wsUrl'] as String : '',
      ticket: res.data!['ticket'] is String ? res.data!['ticket'] as String : '',
      expiresIn: (res.data!['expiresIn'] as num?)?.toInt() ?? 0,
    );
  }
}
