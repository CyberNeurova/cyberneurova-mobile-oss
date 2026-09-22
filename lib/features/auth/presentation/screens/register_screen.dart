import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/terms_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/widgets/social_sign_in_button.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_banner.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _form = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _loading = false;
  String? _error;
  bool _tosAccepted = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      return;
    }
    if (!_tosAccepted) {
      HapticFeedback.mediumImpact();
      setState(() => _error =
          'Please accept the Terms of Service to create an account.');
      return;
    }
    final terms = ref.read(termsProvider).valueOrNull;
    if (terms == null) {
      // Provider still loading or errored. Bail with a friendly message.
      setState(() => _error =
          "Couldn't load the Terms of Service. Check your connection and try again.");
      return;
    }
    HapticFeedback.lightImpact();
    TextInput.finishAutofillContext();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).register(
            email: _email.text.trim(),
            password: _password.text,
            tosVersion: terms.version,
            fullName:
                _name.text.trim().isEmpty ? null : _name.text.trim(),
          );

      if (!mounted) return;
      final l = AppL10n.of(context);
      // Show a "check your email" confirmation, then bounce to login.
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(l.verifyEmailTitle),
          content: Text(l.verifyEmailBody(_email.text.trim())),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l.ok),
            ),
          ],
        ),
      );
      if (mounted) context.pop(); // back to login
    } on DioException catch (e) {
      // ToS error codes from chat-team's inbox/006:
      //   400 TOS_NOT_ACCEPTED  → highlight the checkbox
      //   409 TOS_VERSION_OUTDATED → re-fetch + re-prompt, clear checkbox
      final rawCode =
          e.response?.data is Map ? (e.response!.data as Map)['code'] : null;
      final code = rawCode is String ? rawCode : null;
      if (code == 'TOS_VERSION_OUTDATED') {
        ref.invalidate(termsProvider);
        if (mounted) {
          setState(() {
            _tosAccepted = false;
            _error =
                'The Terms of Service have been updated — please review and re-accept.';
          });
        }
        return;
      }
      if (code == 'TOS_NOT_ACCEPTED') {
        if (mounted) {
          setState(() => _error =
              'Please accept the Terms of Service to continue.');
        }
        return;
      }
      if (mounted) setState(() => _error = _readableError(context, e));
    } catch (e) {
      if (mounted) setState(() => _error = _readableError(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Sahachiel: route through the central mapper so AppException/Dio strings
  // never reach the user (the old 'Instance of' heuristic still leaked them).
  String _readableError(BuildContext ctx, Object e) => userMessageFor(ctx, e);

  @override
  Widget build(BuildContext context) {
    // Register has its own local loading/error (unlike login which uses
    // the global authProvider state) because register doesn't auto-log-in.
    final isLoading = _loading;
    final error = _error;
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: MaxWidthContent(
            maxWidth: 480,
            child: AutofillGroup(
            child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  l.createAccount,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.joinCyberNeurovaFree,
                  style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                if (error != null) ...[
                  ErrorBanner(message: error),
                  const SizedBox(height: 16),
                ],
                CnTextField(
                  controller: _name,
                  focusNode: _nameFocus,
                  label: l.nameOptional,
                  keyboardType: TextInputType.name,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _emailFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                CnTextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  label: l.email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  validator: (v) =>
                      v == null || !v.contains('@') ? l.enterValidEmail : null,
                ),
                const SizedBox(height: 16),
                CnTextField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  label: l.password,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  // newPassword tells iOS to suggest a strong password
                  // and save the email+password as a paired credential.
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) =>
                      v == null || v.length < 8 ? l.passwordMin8 : null,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 16),
                _TosCheckbox(
                  accepted: _tosAccepted,
                  onChanged: (v) => setState(() => _tosAccepted = v),
                ),
                const SizedBox(height: 12),
                CnButton(
                  label: l.createAccount,
                  loading: isLoading,
                  onPressed: _tosAccepted ? _submit : null,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                        child: Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.5))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        l.orDivider,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                        child: Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.5))),
                  ],
                ),
                const SizedBox(height: 20),
                SocialSignInButton.google(),
                // Apple Sign-In is iOS/macOS-only — hide on Android.
                if (defaultTargetPlatform == TargetPlatform.iOS ||
                    defaultTargetPlatform == TargetPlatform.macOS) ...[
                  const SizedBox(height: 12),
                  SocialSignInButton.apple(),
                ],
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: Text(l.alreadyHaveAccount),
                  ),
                ),
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

/// Terms-of-Service acceptance checkbox. Disabled while the terms info is
/// still loading; shows the canonical URLs from the server (so a future
/// legal-text change picks up automatically without a mobile release).
class _TosCheckbox extends ConsumerWidget {
  const _TosCheckbox({required this.accepted, required this.onChanged});
  final bool accepted;
  final ValueChanged<bool> onChanged;

  Future<void> _open(BuildContext ctx, String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider);
    final cs = Theme.of(context).colorScheme;

    return terms.when(
      loading: () => const _TosShimmer(),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Couldn't load Terms of Service. Tap to retry.",
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(termsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (t) => InkWell(
        onTap: () => onChanged(!accepted),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: accepted,
                  onChanged: (v) => onChanged(v ?? false),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: 'I have read and accept the '),
                        TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(
                            color: cs.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizerAdapter(
                              () => _open(context, t.termsUrl)),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                            color: cs.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizerAdapter(
                              () => _open(context, t.privacyUrl)),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TosShimmer extends StatelessWidget {
  const _TosShimmer();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

/// Thin wrapper around TapGestureRecognizer that doesn't require a vsync.
/// Used inside Text.rich spans for the inline ToS / Privacy links.
class TapGestureRecognizerAdapter extends TapGestureRecognizer {
  TapGestureRecognizerAdapter(VoidCallback onTap) {
    this.onTap = onTap;
  }
}
