import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/l10n/locale_provider.dart';
import 'package:cyberneurova_mobile/l10n/supported_locales.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final current = ref.watch(localeProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.language),
      ),
      body: RadioGroup<LanguageEntry?>(
        // Sahachiel: a RadioGroup ancestor now owns the selection — Radio's own
        // groupValue/onChanged are deprecated. A single onChanged handles both
        // the System-default tile (value null) and each language entry.
        groupValue: _matchedEntry(current),
        onChanged: (value) {
          HapticFeedback.selectionClick();
          ref.read(localeProvider.notifier).setLocale(value);
        },
        child: ListView(
          children: [
            // "System default" entry (follow OS locale)
            RadioListTile<LanguageEntry?>(
              value: null,
              title: Row(
                children: [
                  const Text('🌐', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Text(
                    'System default',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              secondary: Text(
                Localizations.localeOf(context).languageCode.toUpperCase(),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
            const Divider(height: 1),
            ...SupportedLocales.all.map((entry) {
              return RadioListTile<LanguageEntry?>(
                value: entry,
                title: Row(
                  children: [
                    Text(entry.flag,
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Text(
                      entry.nativeName,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Maps the active Locale back to a LanguageEntry for selection state.
  LanguageEntry? _matchedEntry(Locale? current) {
    if (current == null) return null;
    for (final e in SupportedLocales.all) {
      if (e.languageCode == current.languageCode &&
          e.scriptCode == current.scriptCode) {
        return e;
      }
    }
    return null;
  }
}
