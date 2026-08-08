import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberneurova_mobile/core/api/interceptors/mobile_context_interceptor.dart';
import 'package:cyberneurova_mobile/l10n/supported_locales.dart';

const _prefsKey = 'app_locale_v1';

/// Holds the user's chosen locale. `null` = follow system.
final localeProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      final entry = LanguageEntry.fromStorageKey(saved);
      if (entry != null) {
        state = entry.locale;
        setApiLocaleOverride(entry.locale);
      }
    }
  }

  Future<void> setLocale(LanguageEntry? entry) async {
    final prefs = await SharedPreferences.getInstance();
    if (entry == null) {
      await prefs.remove(_prefsKey);
      state = null;
      setApiLocaleOverride(null);
    } else {
      await prefs.setString(_prefsKey, entry.storageKey);
      state = entry.locale;
      setApiLocaleOverride(entry.locale);
    }
  }
}
