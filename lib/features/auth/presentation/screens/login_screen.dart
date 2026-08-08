import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/core/layout/responsive.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/widgets/social_sign_in_button.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_text_field.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_button.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_banner.dart';

/// Presents sign-in over whatever the user was doing, instead of navigating.
///
/// The gate used to `pushNamed('login')`. GoRouter drops imperative pushes
/// when a redirect re-evaluates, so the login screen ended up as the ROOT of
/// the stack — and hardware back from it left the app entirely. Verified on
/// device: three pushes in, one back press out to the launcher. A new user
/// typing their first question and changing their mind was ejected from the
/// product.
///
/// A sheet has no such question. Nothing is navigated, back dismisses it,
/// and the chat underneath keeps its composer text — so the send that opened
/// this can simply be retried once there is an account.
///
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
    // Closes itself the moment there is an account, so the caller can carry on
    // with whatever the user was trying to do.
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

  /// True when shown by [showLoginSheet]. A sheet is dismissed, not popped,
  /// so it neither intercepts back nor needs its own back arrow.
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
    // Tell iOS/Android to save these credentials (Keychain / Smart Lock prompts)
    TextInput.finishAutofillContext();
    await ref.read(authProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isLoading = auth.isLoading;
    final error = auth.hasError ? userMessageFor(context, auth.error) : null;
    // Explain an involuntary bounce here (refresh-token loss mid-session) —
    // without this the redirect reads as a random crash back to login.
    final sessionExpired = ref.watch(sessionExpiredProvider);
    ref.listen(authProvider, (_, next) {
      if (next.valueOrNull != null) {
        ref.read(sessionExpiredProvider.notifier).state = false;
      }
    });
    final cs = Theme.of(context).colorScheme;
    final l = AppL10n.of(context);

    // Hardware back from the sign-in wall used to leave the APP, not the
    // screen. A new user taps into the composer, meets a login screen they did
    // not ask for, presses back to think about it — and lands on their home
    // launcher. Verified on device: three route pushes in, one back press out.
    // (GoRouter drops imperative pushes when a redirect re-evaluates, so the
    // stack the pop expects is not there.) Handling it here means back always
    // goes back, whatever the router did with the stack.
    return PopScope(
      canPop: widget.inSheet,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: MaxWidthContent(
                maxWidth: 480,
                child: AutofillGroup(
                child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    // Logo wordmark
                    Text(
                      'CyberNeurova',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        letterSpacing: -0.5,
                      ),
                    ).animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: -0.2, end: 0, duration: 400.ms,
                            curve: Curves.easeOut),
                    const SizedBox(height: 6),
                    Text(
                      l.signInToContinue,
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                    const SizedBox(height: 40),
                    if (error != null) ...[
                      ErrorBanner(message: error)
                          .animate()
                          .fadeIn(duration: 200.ms)
                          .shakeX(duration: 300.ms),
                      const SizedBox(height: 16),
                    ] else if (sessionExpired) ...[
                      ErrorBanner(message: l.errorSessionExpired)
                          .animate()
                          .fadeIn(duration: 200.ms),
                      const SizedBox(height: 16),
                    ],
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
                      validator: (v) => v == null || !v.contains('@')
                          ? l.enterValidEmail
                          : null,
                    ).animate().fadeIn(delay: 150.ms, duration: 300.ms)
                        .slideY(begin: 0.1, end: 0, delay: 150.ms,
                            duration: 300.ms),
                    const SizedBox(height: 16),
                    CnTextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      label: l.password,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      // No minimum on login (backend supports legacy accounts);
                      // just require non-empty so submission isn't a no-op.
                      validator: (v) =>
                          v == null || v.isEmpty ? l.enterYourPassword : null,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 300.ms)
                        .slideY(begin: 0.1, end: 0, delay: 200.ms,
                            duration: 300.ms),
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () =>
                            context.pushNamed('forgot-password'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l.forgotPassword),
                      ),
                    ).animate().fadeIn(delay: 240.ms, duration: 300.ms),
                    const SizedBox(height: 18),
                    CnButton(
                      label: l.signIn,
                      loading: isLoading,
                      onPressed: _submit,
                    ).animate().fadeIn(delay: 280.ms, duration: 300.ms),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                            child: Divider(color: cs.outline.withValues(alpha: 0.4))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            l.orDivider,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                            child: Divider(color: cs.outline.withValues(alpha: 0.4))),
                      ],
                    ).animate().fadeIn(delay: 320.ms, duration: 300.ms),
                    const SizedBox(height: 20),
                    SocialSignInButton.google()
                        .animate()
                        .fadeIn(delay: 360.ms, duration: 300.ms),
                    // Apple Sign-In is iOS/macOS-only (no Android web flow) —
                    // hide the button on Android so it isn't a dead control.
                    if (defaultTargetPlatform == TargetPlatform.iOS ||
                        defaultTargetPlatform == TargetPlatform.macOS) ...[
                      const SizedBox(height: 12),
                      SocialSignInButton.apple()
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 300.ms),
                    ],
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () => context.pushNamed('register'),
                        child: Text(l.dontHaveAccount),
                      ),
                    ).animate().fadeIn(delay: 440.ms, duration: 300.ms),
                    const SizedBox(height: 24),
                    const _PrivacyFooter(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              ),
              ),
            ),
              ),
              // Always a way out. There was no back affordance on this screen
              // at all, so a user who did not want to sign in yet had only the
              // hardware button — the one that was taking them out of the app.
              if (!widget.inSheet)
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: _leave,
                  ),
                ),
            ],
          ),
        ),
      ),
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
}

/// Small "Privacy" link shown at the bottom of auth screens. Required for
/// App Store review and gives users a way to reach the policy without
/// signing in. Opens in the system browser.
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
          'Privacy Policy',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
