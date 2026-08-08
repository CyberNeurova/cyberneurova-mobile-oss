import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cyberneurova_mobile/app/routes.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/l10n/locale_provider.dart';
import 'package:cyberneurova_mobile/l10n/supported_locales.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/theme/theme_mode_provider.dart';

class CyberNeuropvaApp extends ConsumerStatefulWidget {
  const CyberNeuropvaApp({super.key, required this.onReady});

  /// Called once auth state resolves — removes the native splash screen.
  final VoidCallback onReady;

  @override
  ConsumerState<CyberNeuropvaApp> createState() => _CyberNeuropvaAppState();
}

class _CyberNeuropvaAppState extends ConsumerState<CyberNeuropvaApp> {
  bool _splashRemoved = false;

  @override
  void initState() {
    super.initState();
    Animate.restartOnHotReload = true;
  }

  @override
  Widget build(BuildContext context) {
    // Keep rebuilding on auth changes (the router redirect depends on it).
    ref.watch(authProvider);
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    // Remove the OS native splash as soon as the first Flutter frame is up —
    // NOT after auth resolves. Otherwise the static native-splash icon sits on
    // top of the UI and hides the animated Flutter splash for the whole
    // `/auth/me` round-trip, which reads as the logo "hanging". The Flutter
    // SplashScreen itself owns the auth wait + routing.
    if (!_splashRemoved) {
      _splashRemoved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady());
    }

    return MaterialApp.router(
      title: 'CyberNeurova',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      // Switch themes INSTANTLY. The default 200ms AnimatedTheme lerps text and
      // background colors through mid-grey values at the same time, so words
      // briefly become invisible / the screen looks half-changed mid-transition
      // ("words go missing", "crash-like"). Zero duration = clean instant swap.
      themeAnimationDuration: Duration.zero,
      routerConfig: router,

      // ─── Internationalization ──────────────────────────────────────────────
      locale: locale, // null = follow system
      supportedLocales: SupportedLocales.locales,
      localizationsDelegates: AppL10n.localizationsDelegates,
      // Pick the best match for the user's device locale when `locale` is null.
      localeResolutionCallback: (deviceLocale, supported) {
        if (deviceLocale == null) return const Locale('en');
        // Exact match (including script code for Chinese)
        for (final s in supported) {
          if (s.languageCode == deviceLocale.languageCode &&
              s.scriptCode == deviceLocale.scriptCode) {
            return s;
          }
        }
        // Fallback to language code alone
        for (final s in supported) {
          if (s.languageCode == deviceLocale.languageCode) return s;
        }
        return const Locale('en');
      },
    );
  }
}
