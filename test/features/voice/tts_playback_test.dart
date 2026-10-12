import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/api/interceptors/error_interceptor.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/voice/data/repositories/voice_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';
import 'package:cyberneurova_mobile/features/voice/presentation/providers/tts_playback_provider.dart';

/// Listen must not synthesize the same message twice, and a finishing request
/// must not take over a bubble it no longer owns.
///
/// Both faults came from the same place: `toggle` awaits a multi-second
/// network call and then writes state, without checking whether it is still
/// the request that matters.
///
///   * The same-message early return only matched `playing`, so a second tap
///     during the wait fell through to the fetch. The cache is written when
///     the first fetch RETURNS, so it was still empty — a second /tts POST for
///     text already being synthesized. That is real GPU work and a second
///     charge against media credits, in a file whose own header promises
///     re-tapping replays without re-billing.
///
///   * On completion the old code wrote `copyWith(status: playing)`, and
///     copyWith KEEPS activeMessageId. Tap A, then B while A is still
///     loading: A's fetch lands, sets `playing` on a state whose active
///     message is now B, and A's audio plays under B's stop icon. Stopping B
///     stopped audio B never started.
///
/// The stub hangs on a Completer, which is what makes both races reachable:
/// they only exist in the window between the tap and the bytes arriving.
class _StubVoice implements VoiceRepository {
  final List<String> requested = [];

  /// One gate per text, so a test can land an OLD request while a newer one
  /// is still in flight. A single shared gate completes both at once, which
  /// hides exactly the interleaving these tests exist to pin down.
  final Map<String, Completer<Uint8List>> gates = {};

  @override
  Future<Uint8List> synthesize(
    String text, {
    int speaker = 0,
    int maxAudioLengthMs = 30000,
  }) {
    requested.add(text);
    return (gates[text] ??= Completer<Uint8List>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Synthesizes over a real Dio carrying the real [ErrorInterceptor], answered
/// by one canned HTTP response.
///
/// [_StubVoice] throws typed exceptions straight from Dart, and that is how
/// the free-tier test below kept passing while the real thing never reached
/// the paywall: /tts is a bytes request, so the 403 envelope arrived as bytes
/// and the interceptor could not read TIER_REQUIRED out of it.
class _WireVoice implements VoiceRepository {
  _WireVoice(int status, Map<String, Object?> body)
      : _dio = Dio()
          ..httpClientAdapter = _CannedAdapter(status, jsonEncode(body))
          ..interceptors.add(ErrorInterceptor());
  final Dio _dio;

  @override
  Future<Uint8List> synthesize(
    String text, {
    int speaker = 0,
    int maxAudioLengthMs = 30000,
  }) async {
    try {
      final res = await _dio.post<List<int>>(
        '/tts',
        data: {'text': text},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Content-Type': 'application/json'},
        ),
      );
      return Uint8List.fromList(res.data!);
    } on DioException catch (e) {
      // What ApiClient does: rethrow the mapped AppException, not the wrapper.
      throw e.error ?? e;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(body, status, headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubVoice voice;
  late ProviderContainer container;

  setUp(() {
    voice = _StubVoice();
    container = ProviderContainer(
      overrides: [voiceRepositoryProvider.overrideWithValue(voice)],
    );
    addTearDown(container.dispose);
  });

  TtsPlaybackNotifier notifier() =>
      container.read(ttsPlaybackProvider.notifier);
  TtsPlaybackState state() => container.read(ttsPlaybackProvider);

  /// Let the pending toggle run up to its first await without completing it.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a tap starts one synthesis and shows the spinner', () async {
    unawaited(notifier().toggle(messageId: 'm1', text: 'hello'));
    await settle();

    expect(state().activeMessageId, 'm1');
    expect(state().status, TtsPlaybackStatus.loading);
    expect(voice.requested, ['hello']);
  });

  test('tapping again while it loads does not synthesize twice', () async {
    unawaited(notifier().toggle(messageId: 'm1', text: 'hello'));
    await settle();
    unawaited(notifier().toggle(messageId: 'm1', text: 'hello'));
    await settle();

    // The second tap cancels; it must not buy a second WAV.
    expect(voice.requested, hasLength(1));
  });

  test('tapping again while it loads cancels, rather than doing nothing',
      () async {
    unawaited(notifier().toggle(messageId: 'm1', text: 'hello'));
    await settle();
    unawaited(notifier().toggle(messageId: 'm1', text: 'hello'));
    await settle();

    // A spinner you cannot dismiss is its own bug — the button has to be
    // able to take the message back to idle.
    expect(state().status, TtsPlaybackStatus.idle);
    expect(state().activeMessageId, isNull);
  });

  test('switching to another message moves the active id', () async {
    unawaited(notifier().toggle(messageId: 'm1', text: 'first'));
    await settle();
    unawaited(notifier().toggle(messageId: 'm2', text: 'second'));
    await settle();

    expect(state().activeMessageId, 'm2');
    expect(state().status, TtsPlaybackStatus.loading);
    // A different message is different text, so this one IS a new synthesis.
    expect(voice.requested, ['first', 'second']);
  });

  test('a superseded request cannot drag back the bubble that replaced it',
      () async {
    unawaited(notifier().toggle(messageId: 'm1', text: 'first'));
    await settle();
    unawaited(notifier().toggle(messageId: 'm2', text: 'second'));
    await settle();

    // m1 lands late and fails (there is no temp directory under test, so the
    // cache write throws). The user is now waiting on m2, and m1's failure
    // must not touch it — otherwise m2's spinner vanishes and its tap
    // silently did nothing.
    voice.gates['first']!.completeError(Exception('too late'));
    await settle();
    await settle();

    expect(state().activeMessageId, 'm2',
        reason: 'a dead request must not repoint the active message');
    expect(state().status, TtsPlaybackStatus.loading,
        reason: 'm2 is still fetching — its spinner must survive');
  });

  test('a late paywall rejection does not clear the newer bubble', () async {
    // Free tier: the first tap 403s with TIER_REQUIRED. That branch wrote a
    // blank state unconditionally, so a rejection landing after the user had
    // moved to another message wiped THAT message's spinner.
    //
    // The paywall must still fire — they tapped Listen and they are gated —
    // but only the state write is ownership-checked.
    unawaited(notifier().toggle(messageId: 'm1', text: 'first'));
    await settle();
    unawaited(notifier().toggle(messageId: 'm2', text: 'second'));
    await settle();

    voice.gates['first']!.completeError(
        const ForbiddenException('Voice is a paid feature.', 'TIER_REQUIRED'));
    await settle();
    await settle();

    expect(state().activeMessageId, 'm2',
        reason: 'the newer message keeps the floor');
    expect(state().status, TtsPlaybackStatus.loading,
        reason: 'and its spinner survives');
    expect(container.read(pendingPaywallTriggerProvider)?.reason,
        PaywallReason.voiceListen,
        reason: 'the paywall still fires — the user is gated either way');
  });

  test('a 403 TIER_REQUIRED off the wire opens the voice paywall', () async {
    final wired = ProviderContainer(overrides: [
      voiceRepositoryProvider.overrideWithValue(_WireVoice(403, {
        'error': 'Voice is a paid feature.',
        'code': 'TIER_REQUIRED',
      })),
    ]);
    addTearDown(wired.dispose);

    await wired
        .read(ttsPlaybackProvider.notifier)
        .toggle(messageId: 'm1', text: 'hello');

    expect(wired.read(pendingPaywallTriggerProvider)?.reason,
        PaywallReason.voiceListen,
        reason: 'a gated Listen must upsell, not spin and go quiet');
    expect(wired.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
  });

  test('stop() is a no-op when nothing is speaking', () async {
    await notifier().stop();
    expect(state().status, TtsPlaybackStatus.idle);
    expect(state().activeMessageId, isNull);
    expect(voice.requested, isEmpty);
  });
}
