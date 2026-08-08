import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/user/data/repositories/user_repository.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_banner.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull;
    _name = TextEditingController(text: user?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .updateProfile(fullName: _name.text.trim());
      await ref.read(authProvider.notifier).refreshMe();
      if (mounted) context.pop();
    } catch (e) {
      // Sahachiel: map to a localized message; ErrorBanner must never show a
      // raw DioException/stack trace to the user (audit P0 #3).
      if (mounted) setState(() => _error = userMessageFor(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.editProfile),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                CnTextField(
                  controller: _name,
                  label: 'Full name',
                  keyboardType: TextInputType.name,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Name cannot be empty'
                      : null,
                ),
                const SizedBox(height: 24),
                CnButton(
                  label: l10n.save,
                  loading: _loading,
                  onPressed: _save,
                ),

                const SizedBox(height: 32),

                // Credential management — separate screens since each
                // requires password re-entry + has its own warning copy.
                _CredentialRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change password',
                  onTap: () => context.pushNamed('profile-change-password'),
                ),
                const SizedBox(height: 8),
                _CredentialRow(
                  icon: Icons.alternate_email_rounded,
                  label: 'Change email',
                  onTap: () => context.pushNamed('profile-change-email'),
                ),

                const SizedBox(height: 56),

                // Danger zone — kept out of the main settings sheet so casual
                // users can't trip into it. Anyone who wants to delete their
                // account has to come into Edit Profile first.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: cs.error.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Danger zone',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.error,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.deleteAccountConfirm,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.pushNamed('profile-delete'),
                        icon: Icon(
                          Icons.delete_forever_outlined,
                          color: cs.error,
                          size: 18,
                        ),
                        label: Text(
                          l10n.deleteAccount,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: cs.error.withValues(alpha: 0.6)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small list-tile-style row used for credential management entries
/// (Change password, Change email). Matches the visual weight of the
/// settings sheet rows so the user perceives them as routine settings.
class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
