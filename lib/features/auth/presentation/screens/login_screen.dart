import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/widgets/brand_mark.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/widgets/social_sign_in_button.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_banner.dart';

/// Presents sign-in over whatever the user was doing, instead of navigating.
/// (A sheet: back dismisses it, the chat underneath keeps its composer text.)
/// Returns true when the user is signed in by the time it closes.
Future<bool> showLoginSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.94,
      child: _LoginSheet(),
    ),
  );
  return result ?? false;
}

class _LoginSheet extends ConsumerWidget {
  const _LoginSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (_, next) {
      if (next.valueOrNull != null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    });
    return const LoginScreen(inSheet: true);
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.inSheet = false});

  final bool inSheet;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _form = GlobalKey<FormState>();
  bool _obscure = true;

  /// The landing shows the "Continue with…" choices; tapping Email reveals the
  /// email/password form as a second step (reference login flow).
  bool _showEmailForm = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.lightImpact();
    TextInput.finishAutofillContext();
    await ref.read(authProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        );
  }

  /// Leaves the sign-in wall without leaving the app.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('chats');
    }
  }

  void _back() {
    if (_showEmailForm) {
      setState(() => _showEmailForm = false);
    } else {
      _leave();
    }
  }

  void showEmailStep() => setState(() => _showEmailForm = true);
  void toggleObscure() => setState(() => _obscure = !_obscure);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBack = !widget.inSheet || _showEmailForm;

    return PopScope(
      canPop: widget.inSheet && !_showEmailForm,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Subtle brand glow, top-left — theme-aware.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -0.95),
                    radius: 1.3,
                    colors: [
                      cs.primary.withValues(alpha: 0.12),
                      cs.surface.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.55],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Top bar: back (contextual) + settings gear.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                    child: Row(
                      children: [
                        if (showBack)
                          IconButton(
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: _back,
                          )
                        else
                          const SizedBox(width: 48),
                        const Spacer(),
                        IconButton(
                          tooltip: AppL10n.of(context).settings,
                          icon: const Icon(Icons.settings_rounded),
                          onPressed: () => context.pushNamed('settings'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: MaxWidthContent(
                      maxWidth: 480,
                      child: _showEmailForm
                          ? _EmailForm(state: this)
                          : _Landing(state: this),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The "Continue with…" landing ────────────────────────────────────────────

class _Landing extends ConsumerWidget {
  const _Landing({required this.state});

  final _LoginScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);
    final auth = ref.watch(authProvider);
    final error = auth.hasError ? userMessageFor(context, auth.error) : null;
    final sessionExpired = ref.watch(sessionExpiredProvider);
    ref.listen(authProvider, (_, next) {
      if (next.valueOrNull != null) {
        ref.read(sessionExpiredProvider.notifier).state = false;
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          // Hero — a calm, centered promise.
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 56),
                  const SizedBox(height: 28),
                  Text(
                    'A calm space\nto think and create.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your assistant, on every device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // Auth choices, docked near the bottom.
          if (error != null) ...[
            ErrorBanner(message: error),
            const SizedBox(height: 12),
          ] else if (sessionExpired) ...[
            ErrorBanner(message: l.errorSessionExpired),
            const SizedBox(height: 12),
          ],
          _ContinueButton(
            icon: Icons.mail_outline_rounded,
            label: 'Continue with Email',
            onPressed: state.showEmailStep,
          ),
          // Apple Sign-In is iOS/macOS-only (no Android web flow).
          if (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS) ...[
            const SizedBox(height: 12),
            SocialSignInButton.apple(),
          ],
          const SizedBox(height: 12),
          SocialSignInButton.google(),
          const SizedBox(height: 14),
          const _PrivacyFooter(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Uniform "Continue with …" pill.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// ── The email/password step ─────────────────────────────────────────────────

class _EmailForm extends ConsumerWidget {
  const _EmailForm({required this.state});

  final _LoginScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);
    final auth = ref.watch(authProvider);
    final isLoading = auth.isLoading;
    final error = auth.hasError ? userMessageFor(context, auth.error) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AutofillGroup(
        child: Form(
          key: state._form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Sign in',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(l.signInToContinue,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              const SizedBox(height: 28),
              if (error != null) ...[
                ErrorBanner(message: error),
                const SizedBox(height: 16),
              ],
              CnTextField(
                controller: state._email,
                focusNode: state._emailFocus,
                label: l.email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => state._passwordFocus.requestFocus(),
                validator: (v) => v == null || !v.contains('@')
                    ? l.enterValidEmail
                    : null,
              ),
              const SizedBox(height: 16),
              CnTextField(
                controller: state._password,
                focusNode: state._passwordFocus,
                label: l.password,
                obscureText: state._obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => state._submit(),
                validator: (v) =>
                    v == null || v.isEmpty ? l.enterYourPassword : null,
                suffix: IconButton(
                  icon: Icon(
                    state._obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: state.toggleObscure,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => context.pushNamed('forgot-password'),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l.forgotPassword),
                ),
              ),
              const SizedBox(height: 18),
              CnButton(
                label: l.signIn,
                loading: isLoading,
                onPressed: state._submit,
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => context.pushNamed('register'),
                  child: Text(l.dontHaveAccount),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "Privacy" link — required for App Store review; opens the policy in
/// the system browser without needing an account.
class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => launchUrl(
          Uri.parse(AppConstants.privacyPolicyUrl),
          mode: LaunchMode.externalApplication,
        ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'By continuing, you agree to the Terms and Privacy Policy.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
