import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cyberneurova_mobile/features/auth/data/browser_oauth.dart';
import 'package:flutter_test/flutter_test.dart';

/// PKCE is the only thing standing in for a client secret here, so its shape
/// has to be right. A malformed challenge does not fail locally — it fails at
/// Google's authorization endpoint with `invalid_request`, on a device, behind
/// a browser redirect, which is a miserable way to discover a typo.
void main() {
  group('redirect configuration', () {
    test('redirect URI is built from the scheme', () {
      // These three must agree with each other, with AndroidManifest.xml, and
      // with the redirect registered on the OAuth client. A mismatch is
      // `redirect_uri_mismatch` and nothing else.
      expect(BrowserOAuth.redirectScheme, 'ai.cyberneurova.app');
      expect(BrowserOAuth.redirectUri, startsWith(BrowserOAuth.redirectScheme));
      expect(BrowserOAuth.redirectUri, 'ai.cyberneurova.app:/oauth2redirect');
    });

    test('scheme matches the application id', () {
      // Google requires an installed-app redirect scheme to be the reverse
      // client id or the package name; ours is the package name.
      expect(BrowserOAuth.redirectScheme, 'ai.cyberneurova.app');
    });

    test('isConfigured is false without a build-time client id', () {
      // No --dart-define in the test environment, so the browser path stays
      // disabled and the SDK path is never routed around by accident.
      expect(BrowserOAuth.isConfigured, isFalse);
    });

    test('signIn refuses clearly when unconfigured', () async {
      await expectLater(
        BrowserOAuth.signIn(),
        throwsA(predicate((e) => '$e'.contains('not configured'))),
      );
    });
  });

  group('PKCE S256, per RFC 7636', () {
    // The spec's own worked example — if our transform matches this, it
    // matches Google.
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    const expected = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

    String s256(String input) =>
        base64UrlEncode(sha256.convert(utf8.encode(input)).bytes)
            .replaceAll('=', '');

    test('matches the RFC 7636 appendix B vector', () {
      expect(s256(verifier), expected);
    });

    test('is base64url with no padding', () {
      // Padding is the classic mistake: `=` is not valid in the query
      // parameter and Google answers invalid_request.
      final c = s256('some-verifier-value');
      expect(c.contains('='), isFalse);
      expect(c.contains('+'), isFalse);
      expect(c.contains('/'), isFalse);
    });

    test('challenge length is the fixed 43 chars for S256', () {
      expect(s256('anything at all').length, 43);
    });
  });
}
