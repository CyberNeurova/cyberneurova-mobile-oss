import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

/// Google sign-in through the system browser, with PKCE.
///
/// ## Why this exists
///
/// The `google_sign_in` plugin goes through Google Play services, and **Play
/// services refuses apps on an old `targetSdk`**. Measured on the A54: the
/// same signing key and package succeed on the `play` flavour (targetSdk 36)
/// and fail on `direct` (targetSdk 28). Since `direct` is pinned to 28 —
/// that is the only reason it can execute a downloaded rootfs at all
/// (`docs/shell/14-FLAVOURS.md`) — the Linux build could not offer "Continue
/// with Google" no matter what we registered in the console.
///
/// A browser flow does not involve Play services, so it works at any
/// `targetSdk`. Google's own guidance for native apps is exactly this: open a
/// system browser, use PKCE, no client secret.
///
/// ## What it produces
///
/// The **same `id_token`** the plugin returned, so
/// `POST /auth/google {idToken}` is unchanged and the server needs no new
/// verification path. Only the audience differs — see [clientId].
///
/// ## PKCE, and why there is no secret here
///
/// A public client cannot keep a secret: anything shipped in the APK is
/// readable by anyone who downloads it. PKCE replaces the secret with a
/// per-attempt proof — we send `S256(verifier)` up front and the raw verifier
/// at exchange, so an intercepted authorization code is useless without the
/// verifier that never left the device. **Never add a client secret to make
/// this work**; if the exchange rejects the request, the client is registered
/// as the wrong type (it must be an installed/desktop client, not a web one).
class BrowserOAuth {
  const BrowserOAuth._();

  /// OAuth client of type **installed app** (Desktop), NOT the web client.
  ///
  /// Web clients require a secret at token exchange, which a shipped app
  /// cannot hold. Installed-app clients are designed for PKCE without one.
  ///
  /// Because this is a different client from the plugin's, the `id_token` it
  /// mints carries a different `aud`, so the server must accept this id as an
  /// additional audience on `/auth/google`.
  static const String clientId = String.fromEnvironment(
    'GOOGLE_INSTALLED_CLIENT_ID',
  );

  /// Custom scheme registered in `AndroidManifest.xml`. Must match the
  /// redirect URI on the OAuth client exactly, including case.
  static const String redirectScheme = 'ai.cyberneurova.app';
  static const String redirectUri = '$redirectScheme:/oauth2redirect';

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  static bool get isConfigured => clientId.isNotEmpty;

  /// Runs the flow and returns Google's `id_token`.
  ///
  /// Throws with a readable message rather than a raw platform error — this
  /// runs behind a "Continue with Google" button and whatever comes out lands
  /// in front of a user.
  static Future<String> signIn() async {
    if (!isConfigured) {
      throw Exception(
        'Browser sign-in is not configured for this build '
        '(GOOGLE_INSTALLED_CLIENT_ID is unset).',
      );
    }

    final verifier = _randomUrlSafe(64);
    final challenge = _s256(verifier);
    // Bound to this attempt and checked on return. Without it a malicious app
    // registering the same scheme could feed us a code from another session.
    final state = _randomUrlSafe(24);

    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      // `openid email profile` is what yields an id_token with the claims the
      // server reads. Dropping `openid` returns an access token only.
      'scope': 'openid email profile',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      // Always show the picker. Silent re-auth is wrong for an explicit
      // "Continue with Google" tap — a returning user could otherwise never
      // switch account from the app.
      'prompt': 'select_account',
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: redirectScheme,
    );

    final returned = Uri.parse(result);
    final error = returned.queryParameters['error'];
    if (error != null) {
      throw Exception(
        error == 'access_denied' ? 'Sign-in was cancelled.' : 'Google: $error',
      );
    }
    if (returned.queryParameters['state'] != state) {
      // Mismatch means the response is not ours. Refuse it.
      throw Exception('Sign-in could not be verified. Please try again.');
    }
    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('Google did not return an authorization code.');
    }

    final res = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code': code,
        // The proof. No client_secret — see the class doc.
        'code_verifier': verifier,
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Google rejected the sign-in (${res.statusCode}).');
    }

    final body = jsonDecode(res.body);
    final idToken = (body is Map) ? body['id_token'] as String? : null;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google returned no ID token — check that the `openid` scope is '
        'requested and the client is an installed-app client.',
      );
    }
    return idToken;
  }

  static final _rand = Random.secure();

  static String _randomUrlSafe(int bytes) {
    final b = List<int>.generate(bytes, (_) => _rand.nextInt(256));
    return base64UrlEncode(b).replaceAll('=', '');
  }

  static String _s256(String input) =>
      base64UrlEncode(sha256.convert(utf8.encode(input)).bytes)
          .replaceAll('=', '');
}
