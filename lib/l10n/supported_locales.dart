import 'package:flutter/material.dart';

/// Every locale the app ships translations for.
/// Order = display order in the language picker.
class SupportedLocales {
  SupportedLocales._();

  static const List<LanguageEntry> all = [
    LanguageEntry('en', 'English', '🇺🇸'),
    LanguageEntry('es', 'Español', '🇪🇸'),
    LanguageEntry('fr', 'Français', '🇫🇷'),
    LanguageEntry('de', 'Deutsch', '🇩🇪'),
    LanguageEntry('it', 'Italiano', '🇮🇹'),
    LanguageEntry('pt', 'Português', '🇵🇹'),
    LanguageEntry('ru', 'Русский', '🇷🇺'),
    LanguageEntry('zh', '中文 (简体)', '🇨🇳', scriptCode: 'Hans'),
    LanguageEntry('zh', '中文 (繁體)', '🇹🇼', scriptCode: 'Hant'),
    LanguageEntry('ja', '日本語', '🇯🇵'),
    LanguageEntry('ko', '한국어', '🇰🇷'),
    LanguageEntry('ar', 'العربية', '🇸🇦'),
    LanguageEntry('hi', 'हिन्दी', '🇮🇳'),
    LanguageEntry('tr', 'Türkçe', '🇹🇷'),
    LanguageEntry('pl', 'Polski', '🇵🇱'),
    LanguageEntry('nl', 'Nederlands', '🇳🇱'),
    LanguageEntry('vi', 'Tiếng Việt', '🇻🇳'),
    LanguageEntry('id', 'Bahasa Indonesia', '🇮🇩'),
    LanguageEntry('th', 'ไทย', '🇹🇭'),
  ];

  static List<Locale> get locales => all.map((e) => e.locale).toList();
}

class LanguageEntry {
  const LanguageEntry(this.languageCode, this.nativeName, this.flag,
      {this.scriptCode});

  final String languageCode;
  final String nativeName;
  final String flag;
  final String? scriptCode; // For Chinese variants

  Locale get locale => scriptCode != null
      ? Locale.fromSubtags(
          languageCode: languageCode, scriptCode: scriptCode)
      : Locale(languageCode);

  /// Stable key for SharedPreferences storage.
  String get storageKey =>
      scriptCode != null ? '${languageCode}_$scriptCode' : languageCode;

  static LanguageEntry? fromStorageKey(String key) {
    for (final e in SupportedLocales.all) {
      if (e.storageKey == key) return e;
    }
    return null;
  }
}
