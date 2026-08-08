import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberneurova_mobile/core/api/interceptors/mobile_context_interceptor.dart';

const _prefsKey = 'theme_mode_v1';

/// User's chosen theme — System / Light / Dark. Persisted across launches.
/// Defaults to System (follow device) so light-mode users get light on first
/// launch instead of the long-standing dark-only behavior.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    state = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    setApiThemeOverride(_themeHeader(state));
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    setApiThemeOverride(_themeHeader(mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  // Sahachiel: keep the X-Theme request header in sync with the user's theme.
  // 'system' maps to null so the interceptor falls back to live device brightness.
  String? _themeHeader(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => null,
      };
}
