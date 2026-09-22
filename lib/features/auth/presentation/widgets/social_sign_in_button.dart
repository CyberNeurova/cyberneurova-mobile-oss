import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/auth/data/browser_oauth.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';

/// Google **server (web) OAuth client ID**, passed to GoogleSignIn as
/// `serverClientId`. On Android the SDK throws
/// `GoogleSignInException(clientConfigurationError, "serverClientId must be
/// provided on Android")` without it — there's no `google-services.json` in the
/// Android module to supply `default_web_client_id`, so we pass it explicitly.
///
/// This is the chat-team's `GOOGLE_CLIENT_ID` (the web client), which is one of
/// the audiences `/api/mobile/v1/auth/google` accepts when verifying the idToken
/// (`aud`). OAuth *client IDs* are public identifiers (not secrets). Override at
/// build time with `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`; set empty to
/// disable (e.g. once a `google-services.json` is added).
///
/// The default is the CyberNeurova project (440622763104) web client, and it
/// has to be: that is the project both Android OAuth clients live in —
/// `cyberneurova` (Play app-signing SHA-1) and `cyberneurova2` (debug SHA-1) —
/// and Google requires the Android client and the serverClientId to share a
/// project.
///
/// It used to default to `225514883413-l3hagjcug…`, from the old project. That
/// client was DELETED during the migration (submission/play/GOOGLE-SIGNIN-FIX.md,
/// inbox/024), so builds still carrying it cannot mint an id_token at all —
/// Google answers `deleted_client` and the attempt never reaches our aud check.
/// Step 2 of that cutover, "ship a build that sends the new serverClientId",
/// was never merged into lib/, which is why the button worked and then stopped.
/// The server accepts both ids via `GOOGLE_ACCEPTED_CLIENT_IDS`, so this is
/// safe to switch on its own.
const String _googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '440622763104-sbg2vnu21f58cjv9qf7jtgnda3mibnhm.apps.googleusercontent.com',
);

/// Whether the id above was supplied at build time or is the built-in default.
///
/// `hasEnvironment` rather than checking for an empty string, because an
/// explicit `--dart-define=GOOGLE_SERVER_CLIENT_ID=` is a real setting — it
/// disables the id — and must stay distinguishable from not passing one.
///
/// This exists because "works in production, fails in development" is the
/// hardest shape of this bug to reason about, and the serverClientId is the
/// thing most likely to differ between the two: a build made without `.env`
/// silently uses the default, and the Android OAuth client has to live in
/// THAT id's project. Saying which one was used turns a guess into a check.
const bool _serverClientIdFromBuild =
    bool.hasEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Wrapped Google and Apple sign-in buttons. Both go through the existing
/// AuthProvider methods which post to the chat-team's `/auth/google` and
/// `/auth/apple` endpoints.
///
/// **Compliance:** App Store Review Guideline 4.8 requires that any app
/// offering Google (or any third-party) sign-in must also offer Sign in
/// with Apple. These two widgets are designed to be used together — never
/// ship one without the other on iOS.
class SocialSignInButton extends ConsumerStatefulWidget {
  const SocialSignInButton._({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isApple = false,
  });

  final Widget icon;
  final String label;
  final Future<void> Function(WidgetRef ref, BuildContext ctx) onTap;
  final bool isApple;

  factory SocialSignInButton.google() {
    return const SocialSignInButton._(
      icon: _GoogleGlyph(),
      label: 'Continue with Google',
      onTap: _SocialSignInButtonState._handleGoogle,
    );
  }

  factory SocialSignInButton.apple() {
    // Apple glyph color must adapt to the theme — was hardcoded white,
    // which made the icon invisible on light backgrounds.
    return SocialSignInButton._(
      icon: Builder(
        builder: (context) => Icon(
          Icons.apple,
          color: Theme.of(context).colorScheme.onSurface,
          size: 22,
        ),
      ),
      label: 'Continue with Apple',
      onTap: _SocialSignInButtonState._handleApple,
      isApple: true,
    );
  }

  @override
  ConsumerState<SocialSignInButton> createState() =>
      _SocialSignInButtonState();
}

class _SocialSignInButtonState extends ConsumerState<SocialSignInButton> {
  /// True while the provider flow is in flight.
  ///
  /// Without this the button gave zero feedback: you tap, the Google sheet
  /// takes a moment to appear, you pick an account, and then there is a
  /// silent gap while we exchange the id_token with our server — which reads
  /// as "nothing happened", and makes an eventual error dialog feel like it
  /// arrived out of nowhere. It also let you tap twice and start two flows.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = widget.icon;
    final label = widget.label;
    final onTap = widget.onTap;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () async {
          HapticFeedback.lightImpact();
          setState(() => _busy = true);
          try {
            await onTap(ref, context);
          } catch (e) {
            // User-initiated cancel is not an error — both Google and Apple
            // SDKs throw a typed exception when the sheet is dismissed.
            // Silently swallow instead of showing the diagnostic dialog.
            if (_isUserCancel(e)) return;
            if (context.mounted) {
              // Full diagnostic dialog instead of a 6s snackbar — the
              // snackbar truncated the server's actual message making
              // "access denied" recurring bugs hard to pinpoint. Dialog
              // shows the full body + a Copy button so the user can
              // paste the exact error back when reporting.
              final detail = _explainSignInError(e);
              await showDialog<void>(
                context: context,
                builder: (dialogCtx) {
                  final cs = Theme.of(dialogCtx).colorScheme;
                  return AlertDialog(
                    title: Text('Sign-in failed',
                        style: TextStyle(color: cs.onSurface)),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        detail,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          // Sahachiel: copy only the message we actually show, never
                          // the raw Dart stack trace - it's useless in a user bug
                          // report and leaks internal code structure to the clipboard.
                          Clipboard.setData(ClipboardData(text: detail));
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            const SnackBar(
                              content: Text('Error copied'),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Text('Copy'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                },
              );
            }
          } finally {
            // Always clear, including on the cancel path — otherwise
            // dismissing the sheet would leave the button dead.
            if (mounted) setState(() => _busy = false);
          }
        },
        icon: _busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant,
                ),
              )
            : icon,
        label: Text(
          // Naming the step matters: the slow part is our token exchange,
          // not Google, and silence there is what felt broken.
          _busy ? 'Signing in…' : label,
          style: TextStyle(
            color: _busy ? cs.onSurfaceVariant : cs.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static Future<void> _handleGoogle(WidgetRef ref, BuildContext ctx) async {
    // Try Play services first, fall back to the browser.
    //
    // Runtime detection rather than a flavour switch, deliberately: the
    // `direct` build is the reason this exists (Play services refuses its
    // targetSdk 28 — verified on device, same key and package succeed on
    // `play`), but a phone with no Play services at all, or a de-Googled ROM,
    // hits exactly the same wall. Asking the SDK and believing its answer
    // covers every case instead of the one we happened to think of.
    try {
      await _handleGoogleViaPlayServices(ref);
      return;
    } catch (e) {
      if (!BrowserOAuth.isConfigured) rethrow;
      // A cancellation is the user's decision, not a failure to route around
      // — reopening a browser after they backed out would be obnoxious.
      final msg = e.toString().toLowerCase();
      if (msg.contains('cancel')) rethrow;
      final idToken = await BrowserOAuth.signIn();
      await ref.read(authProvider.notifier).loginWithGoogle(idToken);
      return;
    }
  }

  static Future<void> _handleGoogleViaPlayServices(WidgetRef ref) async {
    // GoogleSignIn 7.x. Sign out of the SDK's cached account first so the
    // user always sees the Google account picker. Without this, a returning
    // user with a single cached account is silently re-signed-in and can
    // never switch to a different Google account from the app.
    //
    // The silent-auth path (attemptLightweightAuthentication) is for
    // background re-auth on app launch — never the right fit for an explicit
    // "Continue with Google" button.
    final google = GoogleSignIn.instance;
    await google.initialize(
      // Android REQUIRES serverClientId or authenticate() throws
      // clientConfigurationError. iOS reads its own clientId from
      // GoogleService-Info.plist, so passing this is harmless there.
      serverClientId:
          _googleServerClientId.isEmpty ? null : _googleServerClientId,
    );
    try {
      await google.signOut();
    } catch (_) {
      // No prior session → signOut throws on some SDK versions. Harmless.
    }
    final account = await google.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw Exception("Google didn't return an ID token");
    }
    await ref.read(authProvider.notifier).loginWithGoogle(idToken);
  }

  static Future<void> _handleApple(WidgetRef ref, BuildContext ctx) async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw Exception('Sign in with Apple is only available on Apple devices');
    }
    // Sahachiel: per-login nonce for OIDC replay protection. Apple binds the
    // SHA-256 hash into the returned identity token; we send the RAW nonce to
    // /auth/apple where the server re-hashes and compares. Without it the
    // server's nonce check (docs/API.md) rejects the login / leaves it replayable.
    final rawNonce = _generateNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256ofString(rawNonce),
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw Exception("Apple didn't return an identity token");
    }
    await ref.read(authProvider.notifier).loginWithApple(
          idToken: idToken,
          nonce: rawNonce,
          email: credential.email,
          firstName: credential.givenName,
          lastName: credential.familyName,
          authorizationCode: credential.authorizationCode,
        );
  }
}

/// Sahachiel: cryptographically-random nonce + its SHA-256, for Apple Sign-In
/// replay protection (raw nonce -> server, hashed nonce -> Apple).
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(length, (_) => charset[random.nextInt(charset.length)])
      .join();
}

String _sha256ofString(String input) =>
    sha256.convert(utf8.encode(input)).toString();

/// Recognise SDK-thrown cancellation as "user dismissed the sheet", not
/// an error. Both Google (`GoogleSignInException`) and Apple
/// (`SignInWithAppleAuthorizationException`) raise these with `canceled`
/// in the code or message.
///
/// For Google (google_sign_in 7.x) we MUST use the typed `code` rather than a
/// loose string match: the Credential Manager reports configuration/credential
/// failures (e.g. an unregistered signing SHA-1, no usable credential) with
/// cancel-flavored text, so a string match swallows them — the user taps their
/// account and "nothing happens". Only `GoogleSignInExceptionCode.canceled` is a
/// genuine user dismissal; every other code is a real error and must surface the
/// diagnostic dialog. Apple + any other SDK keep the string fallback so a
/// version bump that changes the exception type can't break cancel detection.
bool _isUserCancel(Object e) {
  if (e is GoogleSignInException) {
    return e.code == GoogleSignInExceptionCode.canceled;
  }
  final s = e.toString().toLowerCase();
  return s.contains('canceled') ||
      s.contains('cancelled') ||
      s.contains('user canceled');
}

/// Pull whatever the server actually said out of a Dio exception so the
/// user sees ACCESS_DENIED / INVALID_TOKEN / ACCOUNT_BLOCKED instead of
/// a generic "Sign-in failed" — we need that detail to debug.
///
/// Includes the request path so we can tell which step failed:
///   POST /auth/google     → token exchange rejected
///   POST /auth/apple      → same
///   GET  /auth/me         → /auth/me race after fresh JWT
String _explainSignInError(Object e) {
  // Google SDK failures never reach our server, so there's no HTTP body to
  // quote — and the raw exception ("GoogleSignInException(code: ...)") tells
  // you nothing about the cause. In practice these are almost always one
  // thing: the signing certificate this build was signed with is not
  // registered as an Android OAuth client for `ai.cyberneurova.app` in the
  // Google Cloud project that owns `serverClientId`. Debug builds and
  // Play-signed builds have DIFFERENT SHA-1s, so a build can work from the
  // Play Store and fail when sideloaded, which is confusing without this note.
  if (e is GoogleSignInException) {
    final buf = StringBuffer()
      ..writeln('Google sign-in failed before reaching our server.')
      ..writeln()
      ..writeln('Code: ${e.code.name}');
    if (e.description != null) buf.writeln('Details: ${e.description}');
    // Two causes, and naming only the first one sent us chasing the wrong
    // thing: the SHA-1 WAS registered, correctly, in a different project.
    // Google requires the Android client and the serverClientId to live in the
    // same Cloud project, and a client in another project looks entirely
    // correct in the console while failing exactly like a missing one.
    final project = _googleServerClientId.split('-').first;
    // The whole essay below is about Android signing certificates, which do
    // not exist on iOS. Handing an iOS build a SHA-1 hunt is the same mistake
    // this comment block records — naming a cause that cannot apply and
    // sending someone off to check it.
    if (PlatformFlags.isIOS) {
      buf
        ..writeln()
        ..writeln('This build needs an iOS OAuth client for bundle id '
            'ai.cyberneurova.app, IN PROJECT $project — the project that '
            'owns:')
        ..writeln(_googleServerClientId)
        ..writeln()
        ..writeln('Three ways this fails, identical from here:')
        ..writeln('1. No iOS client exists for this bundle id, or it lives in '
            'a different Google Cloud project. Same bundle id, wrong project '
            '— Google rejects it and says nothing more specific than this.')
        ..writeln('2. Info.plist is missing the iOS client id, so the SDK '
            'never had one to send.')
        ..writeln('3. The reversed-client-id URL scheme is missing from '
            'Info.plist, so Google cannot hand the result back to the app '
            'and the flow dies on return rather than on launch.')
        ..writeln()
        ..writeln(_serverClientIdFromBuild
            ? 'This id came from GOOGLE_SERVER_CLIENT_ID at build time.'
            : 'This id is the BUILT-IN DEFAULT — no GOOGLE_SERVER_CLIENT_ID '
                'was passed at build time (no .env?).');
      return buf.toString().trim();
    }
    buf
      ..writeln()
      ..writeln('This build needs an Android OAuth client for package '
          'ai.cyberneurova.app carrying its signing SHA-1, IN PROJECT '
          '$project — the project that owns:')
      ..writeln(_googleServerClientId)
      ..writeln()
      ..writeln('Two ways this fails, identical from here:')
      ..writeln('1. The SHA-1 is not registered at all. Debug and sideloaded '
          'builds are signed with the debug key and need their own SHA-1; the '
          'Play build uses the Play app-signing key.')
      ..writeln('2. The SHA-1 IS registered, but in a different Google Cloud '
          'project. Same package, same fingerprint, wrong project — Google '
          'rejects it and says nothing more specific than this. Check the '
          'project number on the Android client matches $project.')
      ..writeln()
      ..writeln(_serverClientIdFromBuild
          ? 'This id came from GOOGLE_SERVER_CLIENT_ID at build time.'
          : 'This id is the BUILT-IN DEFAULT — no GOOGLE_SERVER_CLIENT_ID was '
              'passed at build time (no .env?). If another build of this app '
              'signs in and this one does not, compare that build\'s id '
              'first: the Android client must be in the same project as '
              'whichever id is actually used.');
    return buf.toString().trim();
  }
  if (e is DioException) {
    final status = e.response?.statusCode;
    final path = e.requestOptions.path;
    final method = e.requestOptions.method;
    final body = e.response?.data;
    final buf = StringBuffer();
    buf.writeln('$method $path');
    if (status != null) buf.writeln('HTTP $status');
    if (body is Map) {
      final code = body['code'] as String? ?? body['error'] as String?;
      final msg = body['message'] as String? ?? body['error_description'] as String?;
      if (code != null) buf.writeln('Code: $code');
      if (msg != null) buf.writeln('Message: $msg');
      // Include unknown fields verbatim so we don't lose context if the
      // server adds a new error envelope shape.
      final extra = body.entries
          .where((kv) => !{'code', 'message', 'error', 'error_description'}
              .contains(kv.key))
          .map((kv) => '${kv.key}: ${kv.value}')
          .join('\n');
      if (extra.isNotEmpty) buf.writeln(extra);
    } else if (body != null) {
      buf.writeln('Body: $body');
    }
    if (e.type != DioExceptionType.unknown) {
      buf.writeln('Type: ${e.type.name}');
    }
    return buf.toString().trim();
  }
  return 'Non-HTTP error:\n$e';
}

/// Multi-color "G" glyph drawn inline (no asset needed). Apple's
/// branding doesn't allow custom-color modifications, so we draw the
/// canonical four-quadrant "G". This is a simplified rendering using
/// Google's brand-approved colors.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: Color(0xFF4285F4), // Google blue
          fontFamily: 'sans-serif',
        ),
      ),
    );
  }
}
