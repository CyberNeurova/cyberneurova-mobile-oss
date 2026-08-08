import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/connectivity/connectivity_provider.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/attachments_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_options_menu.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/scope_sheet.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/model_picker.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/message_bubble.dart'
    show showImageFullscreen;
import 'package:cyberneurova_mobile/features/voice/data/repositories/voice_repository.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/authed_network_image.dart';
import 'package:cyberneurova_mobile/shared/widgets/glass_surface.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';
import 'package:cyberneurova_mobile/shared/widgets/pressable_scale.dart';
import 'package:cyberneurova_mobile/core/agent/device_intent.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/device_suggestion_chip.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:go_router/go_router.dart';

// ─── Composer (input bar) ─────────────────────────────────────────────────────

class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.chatId,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onHeightChanged,
  });

  final String chatId;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  /// Fired whenever the composer's laid-out height changes (text wrapping to
  /// a new line, attachment strip appearing, voice bar swapping in). The chat
  /// screen floats the message list UNDERNEATH this bar, so it needs the live
  /// height to pad the list — otherwise the newest bubble hides behind glass.
  final ValueChanged<double>? onHeightChanged;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  bool _hasText = false;
  final _measureKey = GlobalKey();
  double _lastReportedHeight = 0;

  /// Measures the rendered composer after layout and reports changes up.
  /// Post-frame because the height isn't known until the frame is laid out.
  void _reportHeight() {
    if (widget.onHeightChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _lastReportedHeight).abs() < 0.5) return;
      _lastReportedHeight = h;
      widget.onHeightChanged!(h);
    });
  }

  // ── Anchored attach popover (Grok pass) ──────────────────────────────────
  // The + button is a CompositedTransformTarget; the popover overlay follows
  // it via this link, so when the keyboard inset animates away the card
  // tracks the composer instead of floating at a stale position.
  final LayerLink _attachLink = LayerLink();
  OverlayEntry? _attachPopover;

  // ── Press-and-hold voice (WhatsApp-style) ────────────────────────────────
  final AudioRecorder _voiceRecorder = AudioRecorder();
  // GlobalKey on the right-hand mic/send control so its element (and the active
  // long-press recogniser) survives the idle→recording rebuild even though the
  // left-hand children change count/position.
  final GlobalKey _micControlKey = GlobalKey();
  bool _recording = false;
  bool _locked = false; // hands-free after a swipe-up
  bool _pressing = false; // finger is currently held on the mic
  bool _cancelArmed = false; // swiped left far enough to discard on release
  double _dragDy = 0; // finger offset from press origin (up = negative)
  double _dragDx = 0; // (left = negative)
  String? _voicePath;
  DateTime? _voiceStartedAt;
  Timer? _voiceTicker;
  Duration _voiceElapsed = Duration.zero;
  StreamSubscription<Amplitude>? _voiceAmpSub;
  bool _transcribing = false;

  /// Dismissed for this chat. Per-chat and in-memory: someone who has already
  /// said "no, I meant here" should not be asked again in the same
  /// conversation, but a new one starts fresh.
  bool _deviceHintDismissed = false;

  /// Whether what is typed reads as a job for the device. Recomputed on the
  /// controller's listener rather than in build(), so a keystroke only costs a
  /// rebuild when the answer actually changes.
  bool _looksLikeDeviceRequest = false;
  static const int _voiceBarCount = 44;
  final List<double> _voiceLevels = List.filled(_voiceBarCount, 0.08);
  static const Duration _maxVoiceDuration = Duration(minutes: 10);
  // Deliberately large so a natural thumb drift while lifting off does NOT
  // accidentally lock or cancel — release should just send. A real swipe-to-lock
  // / swipe-to-cancel still clears these easily.
  static const double _lockThresholdPx = 96; // drag UP this far → lock
  static const double _cancelThresholdPx = 130; // drag LEFT this far → cancel

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _attachPopover?.remove();
    _attachPopover = null;
    _voiceTicker?.cancel();
    _voiceAmpSub?.cancel();
    _voiceRecorder.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    // Both tracked as TRANSITIONS, not read during build. The listener fires
    // on every keystroke; rebuilding the composer that often is the expensive
    // thing on this screen, and reading controller.text in build() instead
    // would simply never update — the composer only rebuilt when _hasText
    // flipped, so the hint below appeared for "w" and never again.
    final wantsDevice = looksLikeDeviceRequest(widget.controller.text);
    if (has != _hasText || wantsDevice != _looksLikeDeviceRequest) {
      setState(() {
        _hasText = has;
        _looksLikeDeviceRequest = wantsDevice;
      });
    }
  }

  // ── Voice recording control (press-and-hold) ─────────────────────────────
  Future<void> _voiceStart() async {
    if (_recording) return;
    if (!await _voiceRecorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppL10n.of(context).voicePermissionDenied),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    // iOS: force the shared AVAudioSession into speech/record mode before
    // starting. If TTS (just_audio) played earlier, the session is stuck
    // in `playback` — the record package won't override it, so the mic
    // captures silence and the reviewer sees a dead waveform at 0 dB.
    // Apple's 2.1(a) rejection on build 36 traced back to exactly this.
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      await session.setActive(true);
    } catch (e) {
      debugPrint('[voice] audio session configure ERROR: $e');
    }
    HapticFeedback.mediumImpact();
    final dir = await getTemporaryDirectory();
    // WAV (AudioRecord/PCM path) — NOT aacLc. The MediaRecorder path that aacLc
    // uses reports getMaxAmplitude()==0 on Samsung devices → amp.current is
    // -Infinity and the live waveform never moves. WAV uses AudioRecord, which
    // gives real per-tick amplitude. 16 kHz mono ≈ 1.9 MB/min, so even the
    // 10-min cap (~19 MB) stays under the server's 50 MB limit, and Whisper
    // transcribes WAV fine.
    final outPath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _voiceRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: outPath,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _locked = false;
      _cancelArmed = false;
      _dragDy = 0;
      _dragDx = 0;
      _voicePath = outPath;
      _voiceStartedAt = DateTime.now();
      _voiceElapsed = Duration.zero;
      for (var i = 0; i < _voiceBarCount; i++) {
        _voiceLevels[i] = 0.08;
      }
    });
    // Live waveform from the real mic amplitude.
    _voiceAmpSub = _voiceRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 70))
        .listen((amp) {
      // dBFS (≤0). ~-50 = quiet room, ~-10..0 = loud speech. Guard -Infinity
      // (the MediaRecorder path emits it) so the bar rests instead of going NaN.
      final db = amp.current;
      // Map dBFS → 0..1, biased so normal speech (~-40..-20) clearly fills the
      // bar. -58 floor, /44 range, then an ease-out that lifts quiet speech.
      final norm = db.isFinite ? ((db + 58) / 44).clamp(0.0, 1.0) : 0.0;
      final eased = norm * (2 - norm);
      final level = (0.08 + 0.92 * eased).clamp(0.08, 1.0);
      if (!mounted) return;
      // Mutate in place only — the waveform's own AnimationController repaints
      // it at 60fps, so no setState (which would rebuild the whole composer
      // every 70ms) is needed here.
      _voiceLevels.removeAt(0);
      _voiceLevels.add(level);
    });
    _voiceTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_voiceStartedAt == null) return;
      final e = DateTime.now().difference(_voiceStartedAt!);
      if (e >= _maxVoiceDuration) {
        _voiceStop(cancel: false); // hard 10-minute cap
        return;
      }
      if (mounted) setState(() => _voiceElapsed = e);
    });
  }

  void _voiceLock() {
    if (_locked) return;
    HapticFeedback.mediumImpact();
    setState(() => _locked = true);
  }

  void _voiceDragUpdate(LongPressMoveUpdateDetails d) {
    if (!_recording || _locked) return;
    _dragDy = d.offsetFromOrigin.dy;
    _dragDx = d.offsetFromOrigin.dx;
    if (_dragDy < -_lockThresholdPx) {
      _voiceLock();
      return;
    }
    final armed = _dragDx < -_cancelThresholdPx;
    setState(() => _cancelArmed = armed);
  }

  void _voiceDragEnd() {
    if (!_recording) return;
    if (_locked) return; // stays recording; the on-screen buttons take over
    _voiceStop(cancel: _cancelArmed);
  }

  Future<void> _voiceStop({required bool cancel}) async {
    if (!_recording) return;
    _voiceTicker?.cancel();
    await _voiceAmpSub?.cancel();
    _voiceAmpSub = null;
    String? path;
    try {
      path = await _voiceRecorder.stop();
    } catch (e) {
      debugPrint('[voice] recorder.stop ERROR: $e');
    }
    // Release the shared audio session so subsequent TTS playback isn't
    // routed through the earpiece speaker.
    try {
      await (await AudioSession.instance).setActive(false);
    } catch (_) {}
    final elapsed = _voiceElapsed;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _locked = false;
      _pressing = false;
      _cancelArmed = false;
    });
    if (cancel) {
      HapticFeedback.lightImpact();
      return;
    }
    final p = path ?? _voicePath;
    // Ignore an accidental quick tap (< ~600 ms) — there's nothing useful in it.
    if (p == null || elapsed.inMilliseconds < 600) return;
    HapticFeedback.lightImpact();
    await _voiceTranscribeInto(p);
  }

  Future<void> _voiceTranscribeInto(String path) async {
    setState(() => _transcribing = true);
    try {
      final repo = ref.read(voiceRepositoryProvider);
      final text = await repo.transcribe(path);
      if (!mounted) return;
      if (text.trim().isNotEmpty) {
        final existing = widget.controller.text;
        widget.controller.text = existing.isEmpty ? text : '$existing $text';
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
      }
    } catch (e) {
      debugPrint('[voice] transcribe ERROR: $e');
      if (!mounted) return;
      if (e is ForbiddenException && e.code == 'TIER_REQUIRED') {
        ref.read(pendingPaywallTriggerProvider.notifier).state =
            const PaywallTrigger(reason: PaywallReason.voiceSpeak);
      } else {
        // Three cases worth their own wording; everything else goes through
        // the app's shared mapping rather than `e.toString()`, which is what
        // this line used to be — a non-AppException (a socket drop, a type
        // error) landed in the SnackBar verbatim. `_ => e.message` had the
        // same hole from the other side: the server's message is usually
        // written for a person, but not always, and "fetch failed" is what
        // that assumption looks like when it breaks.
        final friendly = e is AppException
            ? switch (e.code) {
                'PAYLOAD_TOO_LARGE' =>
                  'Recording was too long. Try a shorter one.',
                'UPSTREAM_FAILED' =>
                  'Voice transcription is unavailable right now. Try again in '
                      'a minute.',
                'STT_UNAVAILABLE' =>
                  "Voice transcription isn't configured. Try again later.",
                _ => userMessageFor(context, e),
              }
            : userMessageFor(context, e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendly), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final paddingBottom = MediaQuery.of(context).padding.bottom;

    final attachments = ref.watch(pendingAttachmentsProvider(widget.chatId));
    final isOffline = ref.watch(isOfflineProvider);

    _reportHeight();

    // Floating composer group — no full-width bar, no top hairline. The
    // pill sits on the page background with a 12px side margin and an
    // 8px bottom margin + safe area (keyboard inset wins when open).
    return Padding(
      key: _measureKey,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, bottom > 0 ? bottom + 8 : paddingBottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sahachiel: when offline, warn inline and disable send below — the
          // request would otherwise just fail with a network error.
          if (isOffline)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "You're offline. Reconnect to send a message.",
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          // Model picker stays in the app-bar header (not moved in this
          // pass). Web search has no composer toggle anymore — the server
          // auto-detects when a search is needed (the backend API era); the
          // typing indicator still surfaces server-driven search status.
          // Only in chats that genuinely CANNOT act — offering Console from
          // inside Console would be nonsense, and the agent surfaces already
          // say what they can do.
          if (!_deviceHintDismissed &&
              ref.watch(agentSurfaceProvider(widget.chatId)) == null &&
              _looksLikeDeviceRequest)
            DeviceSuggestionChip(
              onOpenConsole: () => context.pushNamed('shell'),
              onDismiss: () => setState(() => _deviceHintDismissed = true),
            ),
          if (attachments.isNotEmpty) ...[
            // 64px thumbnails + 10px headroom baked into each chip so the
            // ✕ circle can overlap the top-right corner without being
            // clipped by the ListView.
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.only(start: 4),
                itemCount: attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _AttachmentChip(
                  attachment: attachments[i],
                  index: i + 1,
                  onRemove: () => ref
                      .read(pendingAttachmentsProvider(widget.chatId).notifier)
                      .remove(attachments[i].id),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Single rounded, CLIPPED input pill that morphs between states
          // (idle / holding-to-record / locked / transcribing). Everything
          // lives inside one rounded Container so nothing (esp. the waveform)
          // can spill outside the box, and there's no separate overlay layer
          // to create a mismatched "black spot".
          _buildComposerPill(cs, isOffline),
        ], // Column children
      ), // Column
    );
  }

  /// Border alpha for the pill + inner chips. Light: the pill fill (#F5F6F9)
  /// is nearly the page color (#ECEEF2), so a 0.35-alpha light-gray border
  /// vanishes and the composer loses its shape — use the full outline there
  /// (same weight the input theme's enabledBorder uses). Dark keeps the
  /// subtle 0.35 hairline.
  double get _outlineAlpha =>
      Theme.of(context).brightness == Brightness.light ? 1.0 : 0.35;

  // ── Composer: one rounded, CLIPPED container that morphs by state ─────────
  Widget _buildComposerPill(ColorScheme cs, bool isOffline) {
    final Widget content;
    if (_transcribing) {
      content = _transcribingRow(cs);
    } else if (_recording && _locked && !_pressing) {
      content = _lockedRow(cs);
    } else if (_recording) {
      // Holding-to-record: a single row. The mic control keeps the same
      // GlobalKey it has in the idle layout, so its element (and the active
      // long-press recogniser) survives the idle→recording rebuild even
      // though the surrounding structure changes (GlobalKey reparenting).
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ..._holdingLeft(cs),
          KeyedSubtree(
              key: _micControlKey, child: _rightControl(cs, isOffline)),
        ],
      );
    } else {
      // Idle (Grok layout): the text field spans the full top row; ALL
      // controls live in a second row at the bottom of the same container —
      // [+ attach] … [mic / send].
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _composerField(cs),
          Row(
            children: [
              _attachButton(cs),
              const SizedBox(width: 6),
              // Model picker sits beside the composer controls (Grok's
              // "Auto" chip) rather than in the app bar, which now carries
              // the Ask ↔ Imagine switch. Flexible so a long model name
              // shrinks instead of overflowing the row.
              const Flexible(child: ModelPickerChip()),
              const Spacer(),
              KeyedSubtree(
                  key: _micControlKey, child: _rightControl(cs, isOffline)),
            ],
          ),
        ],
      );
    }

    // Frosted pill (Grok-style): the composer now FLOATS over the message
    // list, so it's translucent and blurs whatever scrolls beneath it.
    // Previously it was an opaque box laid out below the list, which cut
    // the last bubble off at a hard edge.
    final pill = GlassSurface(
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      // Clip everything to the rounded shape — the waveform can never spill out.
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: content,
    );

    // The lock hint floats ABOVE the mic while holding → unclipped Stack.
    if (_recording && !_locked) {
      final lockProgress = (_dragDy.abs() / _lockThresholdPx).clamp(0.0, 1.0);
      return Stack(
        clipBehavior: Clip.none,
        children: [pill, _floatingLockPill(cs, lockProgress)],
      );
    }
    return pill;
  }

  /// Top row of the idle composer — the multi-line text field, full width,
  /// no inner border (the rounded container IS the field chrome).
  Widget _composerField(ColorScheme cs) {
    return TextField(
      controller: widget.controller,
      maxLines: 6,
      minLines: 1,
      style: TextStyle(fontSize: 16, height: 1.4, color: cs.onSurface),
      textCapitalization: TextCapitalization.sentences,
      maxLength: 16384,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      buildCounter: (context,
          {required currentLength, required isFocused, required maxLength}) {
        if (currentLength < 12000) return null;
        final near = currentLength > 15000;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$currentLength / ${maxLength ?? '?'}',
            style: TextStyle(
                fontSize: 11, color: near ? cs.error : cs.onSurfaceVariant),
          ),
        );
      },
      decoration: InputDecoration(
        hintText: 'Message CyberNeurova...',
        hintStyle: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
        // The rounded container IS the background — turn off the theme's
        // filled box (filled:true/fillColor) that otherwise paints a
        // mismatched rectangle ("black spot") inside it.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        isDense: true,
      ),
    );
  }

  /// The + attach control in the bottom row: a 44dp target drawing a 36dp
  /// outlined circle. Anchor target for the attach popover. Always shown —
  /// every model reads images now via server-side captioning (the backend API §3),
  /// so there is no per-model attach gate anymore.
  Widget _attachButton(ColorScheme cs) {
    return CompositedTransformTarget(
      link: _attachLink,
      child: Tooltip(
        message: 'Attach',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openAttachSheet,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: cs.outline.withValues(alpha: _outlineAlpha)),
                  ),
                  child: Icon(Icons.add_rounded,
                      size: 22, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _holdingLeft(ColorScheme cs) {
    return [
      const SizedBox(width: 10),
      const _RecPulseDot(),
      const SizedBox(width: 10),
      _timerText(cs),
      const SizedBox(width: 12),
      Expanded(
        child: SizedBox(
          height: 40,
          child: _Waveform(levels: _voiceLevels, color: cs.primary),
        ),
      ),
      const SizedBox(width: 8),
      Icon(Icons.keyboard_arrow_left_rounded,
          size: 18, color: _cancelArmed ? cs.error : cs.onSurfaceVariant),
      Text(
        _cancelArmed ? 'cancel' : 'slide to cancel',
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: TextStyle(
            fontSize: 12, color: _cancelArmed ? cs.error : cs.onSurfaceVariant),
      ),
      const SizedBox(width: 6),
    ];
  }

  Widget _timerText(ColorScheme cs) => Text(
        _fmtDuration(_voiceElapsed),
        style: TextStyle(
          fontSize: 13,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: cs.onSurface,
        ),
      );

  Widget _rightControl(ColorScheme cs, bool isOffline) {
    // Mic when the field is empty; morphs to the round send button when
    // text is present. 150ms fade+scale so the swap feels instant but
    // not abrupt.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: widget.sending
          ? _circleActionButton(
              key: const ValueKey('stop'),
              tooltip: 'Stop',
              icon: Icons.stop_rounded,
              background: cs.surfaceContainerHigh,
              foreground: cs.onSurfaceVariant,
              onTap: () {
                HapticFeedback.lightImpact();
                ref
                    .read(chatDetailProvider(widget.chatId).notifier)
                    .stopStreaming();
              },
            )
          : _hasText
              ? _circleActionButton(
                  key: const ValueKey('send'),
                  tooltip: 'Send',
                  icon: Icons.arrow_upward_rounded,
                  background: isOffline ? cs.surfaceContainerHigh : cs.primary,
                  foreground: isOffline ? cs.onSurfaceVariant : cs.onPrimary,
                  onTap: isOffline ? null : widget.onSend,
                )
              : _buildHoldMic(cs),
    );
  }

  /// 44dp circular control (send / stop) with ripple. Disabled when
  /// [onTap] is null — dimmed fill, no splash.
  Widget _circleActionButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      key: key,
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: foreground),
          ),
        ),
      ),
    );
  }

  /// The mic, as a press-and-hold target. Hold → record; slide up to lock,
  /// slide left to cancel, release to send.
  Widget _buildHoldMic(ColorScheme cs) {
    return GestureDetector(
      key: const ValueKey('mic'),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) {
        _pressing = true;
        _voiceStart();
      },
      onLongPressMoveUpdate: _voiceDragUpdate,
      onLongPressEnd: (_) {
        setState(() => _pressing = false);
        _voiceDragEnd();
      },
      onLongPressCancel: () {
        _pressing = false;
        if (_recording && !_locked) _voiceStop(cancel: true);
      },
      onTap: () {
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hold to record · slide up to lock'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.mic_rounded, size: 24, color: cs.onSurfaceVariant),
      ),
    );
  }

  /// Hands-free bar after locking: discard · waveform+timer · send.
  Widget _lockedRow(ColorScheme cs) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: cs.error),
          tooltip: 'Discard',
          onPressed: () => _voiceStop(cancel: true),
        ),
        const _RecPulseDot(),
        const SizedBox(width: 10),
        _timerText(cs),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 40,
            child: _Waveform(levels: _voiceLevels, color: cs.primary),
          ),
        ),
        const SizedBox(width: 8),
        _VoiceCircleButton(
          icon: Icons.arrow_upward_rounded,
          background: cs.primary,
          foreground: cs.onPrimary,
          size: 44,
          onTap: () => _voiceStop(cancel: false),
        ),
      ],
    );
  }

  /// Shown after release while the clip uploads + transcribes.
  Widget _transcribingRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child:
                CircularProgressIndicator(strokeWidth: 2.4, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Text(
            'Transcribing…',
            style: TextStyle(
                fontSize: 14, color: cs.onSurface, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _floatingLockPill(ColorScheme cs, double lockProgress) {
    return Positioned(
      right: 8,
      top: -54 - lockProgress * 8,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.5 + lockProgress * 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Color.lerp(
                  cs.surfaceContainerHighest, cs.primary, lockProgress),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  lockProgress >= 1
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  size: 16,
                  color: lockProgress >= 1 ? cs.onPrimary : cs.onSurface,
                ),
                const SizedBox(height: 2),
                Icon(Icons.keyboard_arrow_up_rounded,
                    size: 14,
                    color:
                        lockProgress >= 1 ? cs.onPrimary : cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// Anchored attach popover (Grok pass) — a rounded card floating just above
  /// the + button, replacing the old full-width bottom sheet. Dismisses on
  /// outside tap; the CompositedTransformFollower keeps it glued to the
  /// button while the keyboard inset animates away.
  /// The `+` menu, as a bottom sheet.
  ///
  /// Was an overlay popover anchored above the button. A sheet is the platform
  /// convention on Android, sits squarely in the thumb zone on a tall phone,
  /// and — the reason it changed — has room for the two entries that were
  /// missing: putting the conversation in a project, and seeing what the agent
  /// is allowed to touch. Both existed already, buried in a 3-dot menu and an
  /// agent screen respectively, which is not where anyone looks for them.
  void _openAttachSheet() {
    HapticFeedback.selectionClick();
    // Dismiss the keyboard BEFORE the sheet opens. `FocusScope.unfocus` alone
    // was not enough on iOS — the OS restored focus when the sheet closed.
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    final l10n = AppL10n.of(context);
    final remaining = _kMaxAttachments -
        ref.read(pendingAttachmentsProvider(widget.chatId)).length;

    // Only an agent session has a scope. Offering this in a plain chat would
    // open a sheet about tools that chat cannot use.
    final isAgent = ref.read(agentSurfaceProvider(widget.chatId)) != null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _popoverRow(cs,
                  icon: Icons.camera_alt_outlined,
                  label: l10n.takePhoto,
                  subtitle: remaining <= 0 ? _kCapHint : null,
                  enabled: remaining > 0,
                  sheetCtx: sheetCtx,
                  onTap: () => _pickImage(ImageSource.camera)),
              _popoverRow(cs,
                  icon: Icons.photo_library_outlined,
                  label: l10n.fromLibrary,
                  subtitle: remaining <= 0 ? _kCapHint : null,
                  enabled: remaining > 0,
                  sheetCtx: sheetCtx,
                  onTap: () => _pickMultipleImages(remaining)),
              _popoverRow(cs,
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Files',
                  subtitle: remaining <= 0 ? _kCapHint : null,
                  enabled: remaining > 0,
                  sheetCtx: sheetCtx,
                  onTap: () => _pickFiles(remaining)),
              Divider(height: 12, color: cs.outline.withValues(alpha: 0.4)),
              _popoverRow(cs,
                  icon: Icons.folder_outlined,
                  label: 'Add to project',
                  subtitle: 'Keep this conversation with related work',
                  enabled: true,
                  sheetCtx: sheetCtx,
                  onTap: () => showProjectPicker(context, ref, widget.chatId)),
              if (isAgent)
                _popoverRow(cs,
                    icon: Icons.shield_outlined,
                    label: 'Tool access',
                    subtitle: 'What the agent may reach on your network',
                    enabled: true,
                    sheetCtx: sheetCtx,
                    onTap: () => showScopeSheet(context, widget.chatId)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static const _kCapHint = 'Up to 5 attachments per message';


  /// One popover action row: icon-in-circle + 15px label (+ optional 12px
  /// subtitle). ≥44px tall. Dismisses the popover before running [onTap] —
  /// same order the old sheet used (Navigator.pop, then the picker).
  Widget _popoverRow(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    String? subtitle,
    required bool enabled,
    required Future<void> Function() onTap,
    required BuildContext sheetCtx,
  }) {
    return InkWell(
      onTap: enabled
          ? () {
              Navigator.of(sheetCtx).pop();
              onTap();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                ),
                child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small caption line at the top of the popover (the per-image billing
  /// hint — the compact stand-in for the old sheet's _AttachInfoBanner).

  /// Per-message cap matches the server policy (the backend API §3a) — also
  /// what image_picker's `limit:` arg enforces at the OS level.
  static const int _kMaxAttachments = 5;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (picked == null) return;

    HapticFeedback.lightImpact();
    final contentType = picked.mimeType ??
        (picked.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg');

    await ref
        .read(pendingAttachmentsProvider(widget.chatId).notifier)
        .add(localPath: picked.path, contentType: contentType);
  }

  /// Multi-pick up to [limit] images. OS enforces the cap.
  /// Each picked image queues its own upload; chips appear in order
  /// they were selected.
  Future<void> _pickMultipleImages(int limit) async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2048,
      limit: limit,
    );
    if (picked.isEmpty) return;

    HapticFeedback.lightImpact();
    final notifier =
        ref.read(pendingAttachmentsProvider(widget.chatId).notifier);
    for (final p in picked) {
      final contentType = p.mimeType ??
          (p.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      // Sequential, not parallel: gives a predictable order in the
      // chip strip and avoids overlapping multipart streams competing
      // for the same Dio connection pool.
      await notifier.add(localPath: p.path, contentType: contentType);
    }
  }

  /// Files picker for non-image attachments. Honors the same 5-item cap.
  Future<void> _pickFiles(int limit) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      // Mirrors the server's SUPPORTED_FILE_TYPES allowlist (the backend API §3c).
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'txt',
        'md',
        'csv',
        'json',
        'zip',
        'py',
        'js',
        'ts',
        'tsx',
        'jsx',
        'go',
        'rs',
        'java',
        'c',
        'cpp',
        'h',
        'hpp',
        'kt',
        'swift',
        'rb',
        'sh',
      ],
    );
    if (result == null || result.files.isEmpty) return;

    HapticFeedback.lightImpact();
    final notifier =
        ref.read(pendingAttachmentsProvider(widget.chatId).notifier);
    final files = result.files.take(limit).toList();
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      await notifier.add(
        localPath: path,
        contentType: _mimeFromExtension(f.extension),
      );
    }
  }

  String _mimeFromExtension(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
      case 'md':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      default:
        return 'text/plain';
    }
  }
}

// (There is no web-search opt-in in the composer anymore — the server
// auto-detects when a search is warranted. webSearchToggleProvider and the
// forceWebSearch plumbing remain in the providers/repository in case an
// explicit opt-in ever returns.)

// ─── Pending attachment chip ─────────────────────────────────────────────────

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.index,
    required this.onRemove,
  });
  final PendingAttachment attachment;

  /// 1-based order index (1, 2, …, 5) shown as a corner badge so the
  /// model can refer to "image 2" and the user sees the same numbering
  /// in the composer. Matches the spec in the backend API §3b.
  final int index;
  final VoidCallback onRemove;

  /// Display name for non-image files — the path basename.
  String get _fileName {
    final segments = attachment.localPath
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? attachment.localPath : segments.last;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isImage = attachment.contentType.startsWith('image/');

    // The 64px card. Images = clipped cover thumbnail; other files = a
    // same-height card with a file icon + truncated monospace name.
    final Widget card = Container(
      height: 64,
      width: isImage ? 64 : null,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage
          // Prefer the local file while we have it — instant render,
          // no network hop. Falls back to the authed remote URL only
          // when the local file is gone.
          ? (File(attachment.localPath).existsSync()
              ? Image.file(File(attachment.localPath), fit: BoxFit.cover)
              : (attachment.upload != null
                  ? AuthedNetworkImage(
                      imageUrl:
                          ApiConstants.resolveImageUrl(attachment.upload!.url),
                      fit: BoxFit.cover,
                    )
                  : const SizedBox.shrink()))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      _fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );

    return Stack(
      children: [
        // 10px headroom (top + end) inside the chip so the ✕ circle can
        // overlap the card corner while staying inside the ListView's clip.
        Padding(
          padding: const EdgeInsets.only(top: 10, right: 10),
          child: Stack(
            children: [
              GestureDetector(
                // Tap an image thumbnail to preview it full-screen before
                // sending.
                onTap: isImage
                    ? () => showImageFullscreen(context,
                        url: attachment.upload?.url ?? '',
                        localPath: attachment.localPath)
                    : null,
                child: card,
              ),
              if (attachment.uploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.scrim.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.primary),
                      ),
                    ),
                  ),
                ),
              if (attachment.error != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      // Tap the red overlay to see what actually went
                      // wrong — and to retry. The error was previously
                      // buried in notifier state with no way to read it.
                      showDialog(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('Upload failed'),
                          content: Text(attachment.error!),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                onRemove();
                              },
                              child: const Text('Remove'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogCtx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      alignment: Alignment.center,
                      child:
                          Icon(Icons.error_outline, color: cs.error, size: 20),
                    ),
                  ),
                ),
              // Order badge — bottom-left so it reads "1", "2", "3"
              // matching the order the model sees in the markdown payload.
              Positioned(
                bottom: 2,
                left: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimary,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ✕ remove — a 24px circle overlapping the card's top-right corner,
        // with a 44px opaque hit area so it's comfortably tappable.
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onRemove();
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHighest,
                    border:
                        Border.all(color: cs.outline.withValues(alpha: 0.35)),
                  ),
                  child:
                      Icon(Icons.close_rounded, size: 14, color: cs.onSurface),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pulsing red "recording" dot.
class _RecPulseDot extends StatefulWidget {
  const _RecPulseDot();
  @override
  State<_RecPulseDot> createState() => _RecPulseDotState();
}

class _RecPulseDotState extends State<_RecPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.25).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Live mic waveform — rounded bars whose heights track the rolling amplitude
/// [levels] (newest on the right), scrolling like a dictation UI.
/// Live mic waveform. Self-animates at 60fps via an internal controller so it's
/// always visibly "listening" (a gentle travelling wave) even in silence; the
/// real mic level (mutated into [levels] each amplitude tick) spikes over the
/// idle wave when the user actually speaks. Driving the repaint from the
/// controller — not a 70ms setState on the whole composer — keeps it smooth.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.levels, required this.color});
  final List<double> levels;
  final Color color;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fill whatever the parent gives us (no fixed height) so we never overflow.
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.infinite,
        painter: _WaveformPainter(widget.levels, widget.color, _c.value),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.levels, this.color, this.phase);
  final List<double> levels;
  final Color color;
  final double phase; // 0..1 — drives the idle "listening" wave

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || levels.isEmpty) return;
    // Fixed-size bars; draw exactly as many as fit the width so they NEVER
    // overflow and always look consistent regardless of the slot width.
    const barW = 3.0;
    const gap = 3.0;
    const unit = barW + gap;
    final n = (size.width / unit).floor().clamp(1, levels.length);
    final denom = n > 1 ? n - 1 : 1;
    final totalW = n * unit - gap;
    var x = (size.width - totalW) / 2;
    final cy = size.height / 2;
    final t = phase * 2 * math.pi;
    final start = levels.length - n; // show the newest n samples
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      // Idle travelling wave so the bar is never dead-flat — real speech spikes
      // over it.
      final idle = 0.10 + 0.09 * (0.5 + 0.5 * math.sin(t + i * 0.5));
      final lvl = levels[start + i].clamp(0.04, 1.0);
      final h = (lvl > idle ? lvl : idle) * (size.height * 0.9);
      // Older bars (left) fade slightly so the newest signal reads strongest.
      final fade = 0.45 + 0.55 * (i / denom);
      paint.color = color.withValues(alpha: fade);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x + barW / 2, cy), width: barW, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
      x += unit;
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}

/// Round icon button for the voice sheet (cancel / send), with press-scale +
/// haptic. Disabled (dimmed, non-tappable) when [onTap] is null.
class _VoiceCircleButton extends StatelessWidget {
  const _VoiceCircleButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.size,
    required this.onTap,
  });
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return PressableScale(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, color: foreground, size: size * 0.42),
        ),
      ),
    );
  }
}
