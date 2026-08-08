import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/user/data/repositories/user_repository.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_banner.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState
    extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_form.currentState!.validate()) return;
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${l.deleteAccount}?'),
        content: Text(l.deleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              l.delete,
              style: TextStyle(
                  color: Theme.of(dialogCtx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .deleteAccount(password: _password.text);
      // Server invalidates tokens; force a clean logout client-side too.
      await ref.read(authProvider.notifier).logout();
      // Router redirects to /auth/login automatically.
    } catch (e) {
      // Sahachiel: map to a localized message; a delete failure (wrong password,
      // network) must read as a clean error, not a raw DioException (audit P0 #3).
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.deleteAccount),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: cs.error, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.deleteAccountConfirm,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                CnTextField(
                  controller: _password,
                  label: l10n.password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  // No validator — the field is OPTIONAL. A Google or Apple
                  // user never set a password, and a required-empty check here
                  // was the whole reason they could not delete their own
                  // account (Apple 5.1.1(v)). The server verifies the password
                  // only when the account has one; the confirm phrase the
                  // repository sends is the real guard.
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.deleteAccountPasswordOptional,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _delete,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: Colors.white,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : Text(l10n.deleteAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
