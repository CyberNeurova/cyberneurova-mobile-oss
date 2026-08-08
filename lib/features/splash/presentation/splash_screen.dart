import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/legal/presentation/screens/privacy_consent_screen.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/widgets/cyberneurova_logo_animation.dart';

/// First screen the user sees on cold launch. Plays a brief letter-by-letter
/// reveal of the CyberNeurova wordmark while auth state resolves in the
/// background, then routes to either `/chats` or `/auth/login`.
///
/// Replaces the previous flash-of-login-screen during init.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _routed = false;
  bool _playAnimation = false; // assume "no" until prefs answer

  static const _word = 'CyberNeurova';

  /// Must cover the WHOLE reveal or the wordmark gets cut off mid-animation.
  /// The last element to appear is the progress dot: it starts at
  /// `950 + 60*12 + 400 = 2070ms` and fades in over 400ms, so the animation
  /// isn't visually complete until ~2470ms. The old 2050 budget cut the tail
  /// off — which is exactly the "the name only shows half way" report.
  static const _minDisplayMs = 2500;

  /// "YYYY-MM-DD:n" — the day the intro last played and how many times it has
  /// played on that day.
  static const _prefsKey = 'splash_plays_v2';

  /// The intro is brand, not a loading screen: seeing it on every single
  /// launch turns a 2-second flourish into a 2-second tax. Twice a day keeps
  /// it feeling deliberate — roughly the first launch of a morning and of an
  /// evening — while every other launch opens straight into the app.
  static const _maxPlaysPerDay = 2;

  /// Returns true if the intro may play now, recording the play if so.
  Future<bool> _claimPlaySlot(SharedPreferences prefs) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final stored = prefs.getString(_prefsKey) ?? '';
    final parts = stored.split(':');
    final sameDay = parts.length == 2 && parts[0] == today;
    final playsToday = sameDay ? (int.tryParse(parts[1]) ?? 0) : 0;

    if (playsToday >= _maxPlaysPerDay) return false;
    await prefs.setString(_prefsKey, '$today:${playsToday + 1}');
    return true;
  }

  @override
  void initState() {
    super.initState();
    _waitAndRoute();
  }

  /// Completes as soon as [authProvider] leaves its loading state — no
  /// polling. Replaces the previous 50ms busy-wait loop.
  ///
  /// Hard-capped at [_authWaitCap]: getMe() rides Dio's 15s connect + 90s
  /// receive timeouts, and a flaky network used to leave users stuck on
  /// this screen for the full duration (reported post-launch). Past the
  /// cap we route anyway — every destination handles both guest and
  /// signed-in states, and the session simply hydrates in the background.
  Future<void> _authResolved() {
    if (!ref.read(authProvider).isLoading) return Future.value();
    final completer = Completer<void>();
    late final ProviderSubscription<Object?> sub;
    sub = ref.listenManual<Object?>(authProvider, (_, __) {
      if (!ref.read(authProvider).isLoading && !completer.isCompleted) {
        completer.complete();
        sub.close();
      }
    });
    return completer.future.timeout(_authWaitCap, onTimeout: () {
      sub.close();
    });
  }

  static const _authWaitCap = Duration(seconds: 6);

  Future<void> _waitAndRoute() async {
    final prefs = await SharedPreferences.getInstance();

    // Animation policy: at most [_maxPlaysPerDay] plays per calendar day,
    // regardless of sign-in state. The previous rule ("play unless signed in
    // and seen before") meant signed-out users — and anyone whose /auth/me
    // was still in flight — sat through the intro on every launch.
    final shouldPlay = await _claimPlaySlot(prefs);
    if (!mounted) return;

    // Instrument Serif is now BUNDLED (pubspec `fonts:`), so there is nothing
    // to wait for — the glyphs are in the binary and the reveal renders in the
    // right face from its first frame. This used to await
    // GoogleFonts.pendingFonts() because the font was fetched from the CDN at
    // runtime and arriving mid-animation re-laid-out the letters, which is
    // what read as the wordmark freezing / drawing half way.
    if (shouldPlay) setState(() => _playAnimation = true);

    // Clock starts when the animation actually starts.
    //
    // The old code started it before awaiting auth, but only mounted the
    // wordmark AFTER auth resolved — so the intro's time budget was spent on
    // the network. Fast auth left ~1.8s for a ~2.5s animation (truncated
    // reveal); auth slower than the budget left ZERO (the wordmark mounted
    // and was routed away in the same breath, reading as a freeze).
    final animClock = Stopwatch()..start();

    // Auth now resolves CONCURRENTLY with the intro rather than gating it.
    // We no longer branch on loggedIn here — /chats accepts both signed-in
    // and guest users, and the router redirect + chat_detail send handler
    // enforce login only when the user actually tries to send.
    await _authResolved();
    if (!mounted) return;

    if (shouldPlay) {
      final remaining = _minDisplayMs - animClock.elapsedMilliseconds;
      if (remaining > 0) {
        await Future.delayed(Duration(milliseconds: remaining));
      }
    }

    if (!mounted || _routed) return;
    _routed = true;
    // First-launch privacy consent (Apple 5.1.1(i)/5.1.2(i)) takes
    // precedence over anything else — before the user can even see the
    // chat shell we have to disclose what leaves the device and get an
    // explicit tap. Consent is one-time per install; a returning user
    // (SharedPreferences flag set) goes straight to the chat shell.
    final needsConsent = !await PrivacyConsentScreen.alreadyAccepted();
    if (!mounted) return;
    context.goNamed(needsConsent ? 'consent' : 'chats');
  }

  @override
  Widget build(BuildContext context) {
    // Always render the mark from the first frame (don't gate on async state) —
    // otherwise the first Flutter frame is a bare navy screen and the logo
    // briefly vanishes between the OS native-splash icon and the animation,
    // which reads as a flicker/hang. Drawing it immediately makes the handoff
    // from the native splash seamless.
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The brand mark animates first — a "neuron firing": soma pops in,
            // dendrites grow, a signal pulses up the axon, the synaptic dots
            // spark. The wordmark then reveals beneath as the dots light up.
            const CyberNeurovaLogoAnimation(
              size: 124,
              color: AppTheme.accent,
              duration: Duration(milliseconds: 1750),
            ),
            const SizedBox(height: 30),
            // Letter-by-letter wordmark with a soft teal glow that ripples
            // left-to-right across the letters as they appear. The shimmer is
            // produced by flutter_animate's `shimmer` effect chained after
            // each letter's fade-in. Delayed ~950ms so it arrives with the
            // synapse's "fire" beat.
            // Only mounted when the intro actually plays (first install /
            // logged-out). Returning users route out in a few hundred ms —
            // starting a 950ms-delayed letter reveal for them just means an
            // invisible row that gets cut off mid-animation.
            if (_playAnimation)
            DefaultTextStyle(
              style: AppTheme.serifDisplay(
                size: 44,
                weight: FontWeight.w400,
              ).copyWith(
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: AppTheme.accent.withValues(alpha: 0.55),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _word.length; i++)
                    Text(_word[i])
                        .animate(delay: Duration(milliseconds: 950 + 60 * i))
                        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                        .slideY(
                          begin: 0.25,
                          end: 0,
                          duration: 280.ms,
                          curve: Curves.easeOutCubic,
                        )
                        .shimmer(
                          delay: 200.ms,
                          duration: 700.ms,
                          color: AppTheme.accent,
                        ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Subtle progress dot underneath, fades in last.
            if (_playAnimation)
            Container(
              width: 28,
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(1),
              ),
            )
                .animate(delay: (950 + 60 * _word.length + 400).ms)
                .fadeIn(duration: 400.ms)
                .shimmer(
                  duration: 1200.ms,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
          ],
        ),
      ),
    );
  }
}
