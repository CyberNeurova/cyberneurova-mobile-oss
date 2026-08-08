import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';

// Sahachiel: isOwnOrigin decides whether the user's Bearer token is attached to
// an image/asset request. A false positive leaks the access token to a third
// party, so lock the rules: https-only AND exact host:port of our web origin.
// These run against the default baseUrl (https://cyberneurova.ai/api/mobile/v1)
// since CI passes no API_BASE_URL define, so webOrigin == https://cyberneurova.ai.
void main() {
  group('ApiConstants.isOwnOrigin', () {
    test('true for an https URL on our exact host', () {
      expect(
        ApiConstants.isOwnOrigin('https://cyberneurova.ai/api/images/abc/view'),
        isTrue,
      );
    });

    test('false for a different host', () {
      expect(
        ApiConstants.isOwnOrigin('https://evil.example.com/steal.png'),
        isFalse,
      );
    });

    test('false for a subdomain of our host', () {
      expect(
        ApiConstants.isOwnOrigin('https://cdn.cyberneurova.ai/x.png'),
        isFalse,
      );
    });

    test('false for http (cleartext) even on our own host', () {
      expect(
        ApiConstants.isOwnOrigin('http://cyberneurova.ai/x.png'),
        isFalse,
      );
    });

    test('false when an explicit non-default port is present', () {
      expect(
        ApiConstants.isOwnOrigin('https://cyberneurova.ai:8443/x.png'),
        isFalse,
      );
    });

    test('false for scheme-relative or unparseable input', () {
      expect(ApiConstants.isOwnOrigin('//cyberneurova.ai/x.png'), isFalse);
      expect(ApiConstants.isOwnOrigin('javascript:alert(1)'), isFalse);
      expect(ApiConstants.isOwnOrigin('not a url'), isFalse);
    });
  });
}
