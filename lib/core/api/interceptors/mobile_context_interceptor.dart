import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Adds device/app context to every request so the backend (and the AI) can
/// adapt responses for a mobile environment — chart sizes, code formatting,
/// links that work in-app, etc.
///
/// Headers added:
///   X-Platform: ios | android
///   X-OS-Version: 26.6
///   X-App-Version: 1.0.0+1
///   X-Screen-Size: 390x844
///   X-Locale: fr (BCP-47 language tag — chat-team uses this to set
///                 system-prompt language via `requestHints.language`)
///   X-Theme: light | dark (reflects the user's chosen theme; system follows
///                          the device brightness)
///
/// Static-platform headers are cached after first construction. The locale
/// header is re-evaluated on every request because the user can pick a
/// different language at runtime via the in-app picker.
class MobileContextInterceptor extends Interceptor {
  MobileContextInterceptor() {
    _initialize();
  }

  Map<String, String> _staticHeaders = const {};
  bool _initialized = false;

  Future<void> _initialize() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final view =
          WidgetsBinding.instance.platformDispatcher.implicitView;
      final size = view?.physicalSize;
      final dpr = view?.devicePixelRatio ?? 1.0;
      final width = size != null ? (size.width / dpr).round() : 0;
      final height = size != null ? (size.height / dpr).round() : 0;

      _staticHeaders = {
        'X-Platform': Platform.isIOS ? 'ios' : 'android',
        'X-OS-Version': Platform.operatingSystemVersion,
        'X-App-Version': '${info.version}+${info.buildNumber}',
        if (width > 0) 'X-Screen-Size': '${width}x$height',
      };
      _initialized = true;
    } catch (_) {
      _staticHeaders = {
        'X-Platform': Platform.isIOS ? 'ios' : 'android',
      };
      _initialized = true;
    }
  }

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    if (_initialized) {
      options.headers.addAll(_staticHeaders);
    }
    options.headers['X-Locale'] = _resolveLocale();
    options.headers['X-Theme'] = _resolveTheme();
    handler.next(options);
  }

  /// Read user-selected locale first; fall back to device locale. We send the
  /// BCP-47 language code only (e.g. "fr", not "fr_FR") — the chat-team uses
  /// this to set the AI's reply language; country variants don't help and just
  /// cost us false misses when their server normalises.
  String _resolveLocale() {
    final override = _apiLocaleOverride;
    if (override != null && override.languageCode.isNotEmpty) {
      return override.languageCode;
    }
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    return device.languageCode.isNotEmpty ? device.languageCode : 'en';
  }

  /// Sahachiel: X-Theme used to be hardcoded 'dark'. Resolve it from the user's
  /// chosen theme (set via setApiThemeOverride); ThemeMode.system maps to null
  /// here and falls back to the live device brightness, so the backend/AI can
  /// render artifacts to match what the user actually sees.
  String _resolveTheme() {
    final override = _apiThemeOverride;
    if (override == 'light' || override == 'dark') return override!;
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? 'dark' : 'light';
  }
}

// ─── Global locale override ─────────────────────────────────────────────────
// Updated by the locale provider whenever the user picks a language in-app.
// Kept as a top-level field (not a singleton) so the interceptor can read it
// synchronously inside onRequest without depending on Riverpod.

Locale? _apiLocaleOverride;

void setApiLocaleOverride(Locale? locale) {
  _apiLocaleOverride = locale;
}

// ─── Global theme override ──────────────────────────────────────────────────
// Updated by themeModeProvider when the user changes theme. 'light' | 'dark' |
// null (=> follow the live device brightness). Top-level so onRequest can read
// it synchronously without depending on Riverpod.

String? _apiThemeOverride;

void setApiThemeOverride(String? theme) {
  _apiThemeOverride = theme;
}
