import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/user/data/repositories/user_repository.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';

/// Change password screen. Per the backend API: on success, every
/// session OTHER than the current one is revoked — surfaced as a warning
/// so the user knows their iPad / web sessions will be logged out.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  // One flag per field. They shared a single `_obscure`, so the eye on
  // Current password revealed BOTH — and New password had no eye of its own,
  // which is the field where an unseen typo becomes a password you cannot
  // reproduce.
  bool _obscureCurrent = true;
  bool _obscureNext = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(userRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Other devices signed out.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } on DioException catch (e) {
      final rawCode =
          e.response?.data is Map ? (e.response!.data as Map)['code'] : null;
      final code = rawCode is String ? rawCode : null;
      setState(() => _error = switch (code) {
            'INVALID_CREDENTIALS' => 'Current password is incorrect.',
            'OAUTH_ONLY' =>
              'This account was created with Google or Apple. Use "Forgot Password" to set a password instead.',
            'PASSWORD_UNCHANGED' =>
              'New password must be different from your current one.',
            'INVALID_INPUT' => 'Password must be at least 6 characters.',
            _ => "Couldn't change password. Please try again.",
          });
    } catch (_) {
      setState(() => _error = "Couldn't change password. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Change password'),
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Changing your password will sign you out of all other devices.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],
                CnTextField(
                  controller: _current,
                  label: 'Current password',
                  obscureText: _obscureCurrent,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureCurrent
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                const SizedBox(height: 16),
                CnTextField(
                  controller: _next,
                  label: 'New password',
                  obscureText: _obscureNext,
                  validator: (v) => v == null || v.length < 6
                      ? 'At least 6 characters'
                      : null,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureNext
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureNext = !_obscureNext),
                  ),
                ),
                const SizedBox(height: 24),
                CnButton(
                  label: 'Update password',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
