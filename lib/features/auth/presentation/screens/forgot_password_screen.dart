import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/auth/data/repositories/auth_repository.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_banner.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();

  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
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
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);

    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: SingleChildScrollView(
              child: MaxWidthContent(
                maxWidth: 480,
                child: _sent
                  ? _SentConfirmation(email: _email.text.trim())
                  : Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            l.resetPassword,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ).animate().fadeIn(duration: 300.ms),
                          const SizedBox(height: 8),
                          Text(
                            l.resetPasswordHint,
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ).animate().fadeIn(
                              delay: 80.ms, duration: 300.ms),
                          const SizedBox(height: 28),
                          if (_error != null) ...[
                            ErrorBanner(message: _error!)
                                .animate()
                                .fadeIn(duration: 200.ms)
                                .shakeX(duration: 300.ms),
                            const SizedBox(height: 16),
                          ],
                          CnTextField(
                            controller: _email,
                            label: l.email,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => v == null || !v.contains('@')
                                ? l.enterValidEmail
                                : null,
                          )
                              .animate()
                              .fadeIn(delay: 160.ms, duration: 300.ms)
                              .slideY(
                                  begin: 0.1,
                                  end: 0,
                                  delay: 160.ms,
                                  duration: 300.ms),
                          const SizedBox(height: 28),
                          CnButton(
                            label: l.sendResetLink,
                            loading: _loading,
                            onPressed: _submit,
                          ).animate().fadeIn(
                              delay: 240.ms, duration: 300.ms),
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton(
                              onPressed: () => context.pop(),
                              child: Text(l.backToSignIn),
                            ),
                          ).animate().fadeIn(
                              delay: 320.ms, duration: 300.ms),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
  }
}

class _SentConfirmation extends StatelessWidget {
  const _SentConfirmation({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: 0.15),
          ),
          child: Icon(Icons.mark_email_read_rounded,
                  size: 44, color: cs.primary)
              .animate()
              .scaleXY(
                  begin: 0.5,
                  end: 1.0,
                  duration: 400.ms,
                  curve: Curves.elasticOut),
        ).animate().scaleXY(begin: 0.0, end: 1.0, duration: 400.ms),
        const SizedBox(height: 24),
        Text(
          l.checkYourEmail,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l.resetSentBody(email),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ).animate().fadeIn(delay: 280.ms, duration: 300.ms),
        const SizedBox(height: 40),
        FilledButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          child: Text(l.backToSignIn),
        ).animate().fadeIn(delay: 360.ms, duration: 300.ms),
      ],
    );
  }
}
