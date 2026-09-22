import 'package:cyberneurova_mobile/features/user/presentation/providers/usage_provider.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/usage_row_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/user_model.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/archived_chats_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/l10n/locale_provider.dart';
import 'package:cyberneurova_mobile/l10n/supported_locales.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/shared/theme/theme_mode_provider.dart';
import 'package:cyberneurova_mobile/shared/widgets/upgrade_pill.dart';

/// Full-screen Settings route (`/settings`). Replaces the old modal settings
/// sheet — sub-screens are plain pushes, so "back" from (e.g.) Capabilities
/// returns here naturally. No pop→push→reopen hack.
///
/// Like the sheet it replaces, the screen is browsable without an account
/// (Apple 5.1.1(v)): unauthenticated users see a Sign in card plus the
/// Preferences group (language + appearance); account-scoped groups are
/// hidden.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final l = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settings),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: MaxWidthContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Unauthenticated: swap the profile header + account-scoped
              // groups for a single "Sign in" card. Preferences (language /
              // appearance) stay visible so the settings surface is still
              // meaningfully browsable without an account.
              if (user == null) ...[
                const _SignInCard(),
                const SizedBox(height: 12),
              ] else ...[
                _ProfileHeader(user: user),
                const SizedBox(height: 16),

                // ── Account ──
                _SectionHeader(label: l.account),
                _SettingsCard(
                  children: [
                    _SettingRow(
                      icon: Icons.person_outline_rounded,
                      label: l.profile,
                      onTap: () => context.pushNamed('profile-edit'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.alternate_email_rounded,
                      // No l10n key exists — matches the sub-screen's own
                      // (hardcoded) AppBar title.
                      label: 'Change email',
                      onTap: () => context.pushNamed('profile-change-email'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.lock_outline_rounded,
                      label: l.changePassword,
                      onTap: () => context.pushNamed('profile-change-password'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.devices_other_rounded,
                      label: l.activeSessions,
                      onTap: () => context.pushNamed('profile-sessions'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── AI (account-scoped: per-user prompts, projects, memory,
                // capability toggles) ──
                _SettingsCard(
                  children: [
                    _SettingRow(
                      icon: Icons.psychology_alt_outlined,
                      label: l.memory,
                      onTap: () => context.pushNamed('profile-memory'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.tune_rounded,
                      label: l.customPrompts,
                      onTap: () => context.pushNamed('profile-prompts'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.extension_outlined,
                      label: l.capabilities,
                      onTap: () => context.pushNamed('profile-capabilities'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.folder_outlined,
                      label: l.projectsTitle,
                      onTap: () => context.pushNamed('profile-projects'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.devices_rounded,
                      label: 'Remote control',
                      onTap: () => context.pushNamed('remote-devices'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // ── App (visible signed out too) ──
              _SettingsCard(
                children: [
                  _SettingRow(
                    icon: Icons.language_rounded,
                    label: l.language,
                    trailing: _langLabel(ref),
                    onTap: () => context.pushNamed('profile-language'),
                  ),
                  const _Sep(),
                  _SettingRow(
                    icon: Icons.contrast_rounded,
                    label: 'Appearance',
                    trailing: _appearanceLabel(ref),
                    onTap: () => _showAppearancePicker(context, ref),
                  ),
                  const _Sep(),
                  _SettingRow(
                    icon: Icons.archive_outlined,
                    label: 'Archived chats',
                    trailing: _archivedCount(ref),
                    onTap: () => context.pushNamed('archived-chats'),
                  ),
                  if (user != null) ...[
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.show_chart_rounded,
                      label: l.usageLabel,
                      // The number that is actually counting.
                      //
                      // `user.tokens` is the legacy counter; on a v2 account it
                      // stays at zero while the weekly bucket fills, so this
                      // row read "0K / 60000K" on a Pro account after a day of
                      // heavy use — which reads as "nothing you do is counted".
                      trailing: usageRowValue(
                        usage: ref.watch(usageDetailProvider).valueOrNull,
                        legacyUsed: user.tokens?.used,
                        legacyLimit: user.tokens?.limit,
                      ),
                      onTap: () => context.pushNamed('usage'),
                    ),
                  ],
                ],
              ),

              // ── Billing — hidden on platforms where PlatformFlags says so
              // (App Store rule lives in one auditable place). ──
              if (user != null && PlatformFlags.showBilling) ...[
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SettingRow(
                      icon: Icons.attach_money_rounded,
                      label: l.billing,
                      // Free tier: swap the plain tier text for the same
                      // compact Upgrade pill as the drawer header. Gated on
                      // the shared PlatformFlags CTA rule (iOS may hide it
                      // while the whole Billing card is visible).
                      trailing: UpgradePill.isFreeTier(user.tier) &&
                              PlatformFlags.showUpgradeCta
                          ? null
                          : _tierLabel(l, user),
                      trailingWidget: UpgradePill.isFreeTier(user.tier) &&
                              PlatformFlags.showUpgradeCta
                          ? UpgradePill(
                              onTap: () =>
                                  context.pushNamed('billing-plans'),
                            )
                          : null,
                      onTap: () => context.pushNamed('billing-plans'),
                    ),
                    const _Sep(),
                    _SettingRow(
                      icon: Icons.receipt_long_outlined,
                      // No l10n key exists — matches the sub-screen's own
                      // (hardcoded) AppBar title.
                      label: 'Billing history',
                      onTap: () => context.pushNamed('billing-history'),
                    ),
                  ],
                ),
              ],

              // ── Sign out — destructive but recoverable; visually
              // separated at the bottom. ──
              if (user != null) ...[
                const SizedBox(height: 24),
                _SettingsCard(
                  children: [
                    _SettingRow(
                      icon: Icons.logout_rounded,
                      label: l.signOut,
                      color: cs.error,
                      onTap: () => _confirmLogout(context, ref, l),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  String? _tierLabel(AppL10n l, UserModel? u) {
    if (u == null) return null;
    return switch (u.tier) {
      'pro_max' => l.proMaxPlan,
      'pro' => l.proPlan,
      'premium' => l.premiumPlan,
      _ => l.freePlan,
    };
  }

  String _appearanceLabel(WidgetRef ref) {
    return switch (ref.watch(themeModeProvider)) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };
  }

  /// Count shown next to the Archived chats row. Intersected with the live
  /// chat list so ids for chats deleted elsewhere aren't counted.
  String? _archivedCount(WidgetRef ref) {
    final ids = ref.watch(archivedChatsProvider);
    if (ids.isEmpty) return null;
    final chats = ref.watch(chatListProvider).valueOrNull;
    if (chats == null) return '${ids.length}';
    final live = chats.where((c) => ids.contains(c.id)).length;
    return live == 0 ? null : '$live';
  }

  Future<void> _showAppearancePicker(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final current = ref.read(themeModeProvider);
    // Use Theme.of(context) — not AppTheme.* constants — so the picker
    // sheet itself reflects the live theme.
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Appearance',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            for (final entry in const [
              (ThemeMode.system, Icons.brightness_auto_rounded, 'System',
                  'Follow device setting'),
              (ThemeMode.light, Icons.light_mode_rounded, 'Light', null),
              (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark', null),
            ])
              ListTile(
                leading: Icon(entry.$2, size: 22, color: cs.onSurfaceVariant),
                title: Text(entry.$3, style: TextStyle(color: cs.onSurface)),
                subtitle: entry.$4 == null
                    ? null
                    : Text(entry.$4!,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                trailing: current == entry.$1
                    ? Icon(Icons.check_rounded, color: cs.primary)
                    : null,
                onTap: () => Navigator.pop(sheetCtx, entry.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(themeModeProvider.notifier).setMode(picked);
    }
  }

  String? _langLabel(WidgetRef ref) {
    final selected = ref.watch(localeProvider);
    if (selected == null) return 'System';
    final entry = SupportedLocales.all.firstWhere(
      (e) =>
          e.languageCode == selected.languageCode &&
          e.scriptCode == selected.scriptCode,
      orElse: () => SupportedLocales.all.first,
    );
    return entry.nativeName;
  }

  void _confirmLogout(BuildContext context, WidgetRef ref, AppL10n l) {
    HapticFeedback.selectionClick();
    // Capture the router before any pops — after logout the settings
    // screen may rebuild/redirect and this element's context goes stale.
    final router = GoRouter.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.signOutQuestion),
        content: Text(l.signOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx); // close dialog
              ref.read(authProvider.notifier).logout();
              // The sheet used to close over the chat surface; the route
              // equivalent is returning to the (public) chat shell.
              router.goNamed('chats');
            },
            child: Text(
              l.signOut,
              style: TextStyle(color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header cards ────────────────────────────────────────────────────────────

/// Avatar + identity at the top of the screen (ports the sheet's email card,
/// plus the drawer's initial-avatar so the surface the user tapped from and
/// the screen read as one identity).
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = (user.name?.isNotEmpty == true ? user.name![0] : user.email[0])
        .toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outline),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.name?.isNotEmpty == true)
                  Text(
                    user.name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: user.name?.isNotEmpty == true ? 13 : 15,
                    fontWeight: user.name?.isNotEmpty == true
                        ? FontWeight.w400
                        : FontWeight.w500,
                    color: user.name?.isNotEmpty == true
                        ? cs.onSurfaceVariant
                        : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown at the top of the settings screen for unauthenticated users.
/// Replaces the whole Account + AI + Sign out stack with a single prominent
/// CTA. Preferences (language + theme) still render below this so the
/// screen stays useful without a login.
class _SignInCard extends StatelessWidget {
  const _SignInCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign in to CyberNeurova',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Save your chats and pick up on any device.',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                GoRouter.of(context).goNamed('login');
              },
              child: const Text('Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable settings card + row ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.trailingWidget,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? trailing;

  /// Widget alternative to [trailing] (e.g. the free-tier Upgrade pill on
  /// the Billing row). Rendered in the same slot, before the chevron.
  final Widget? trailingWidget;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The `color` override is used for destructive actions like Sign out.
    final c = color ?? cs.onSurface;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        // 16/14 padding → ≥50px tall rows (comfortably past the 44px
        // touch-target minimum), on the 4/8 spacing grid.
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c,
                ),
              ),
            ),
            if (trailing != null) ...[
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (trailingWidget != null) ...[
              trailingWidget!,
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 0.5, indent: 16, endIndent: 16);
}
