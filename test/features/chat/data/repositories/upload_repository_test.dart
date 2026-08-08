import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/upload_repository.dart';

// Sahachiel: UploadResult.fromJson is a pure parser for the file-upload
// response. `url` was a bare `as String` (crashes on missing/null) and the other
// fields used `(x ?? default) as String` (still crashes on a present non-string).
// Lock the happy path + the missing / wrong-typed degradation. No mock needed.
void main() {
  group('UploadResult.fromJson', () {
    test('parses a well-formed payload', () {
      final r = UploadResult.fromJson({
        'url': 'https://x/y.png',
        'pathname': 'u/c/y.png',
        'contentType': 'image/png',
        'name': 'y.png',
        'size': 1234,
      });
      expect(r.url, 'https://x/y.png');
      expect(r.pathname, 'u/c/y.png');
      expect(r.contentType, 'image/png');
      expect(r.name, 'y.png');
      expect(r.size, 1234);
    });

    test('uses defaults and does not throw when fields are missing', () {
      final r = UploadResult.fromJson(<String, dynamic>{});
      expect(r.url, '');
      expect(r.pathname, '');
      expect(r.contentType, 'application/octet-stream');
      expect(r.name, '');
      expect(r.size, 0);
    });

    test('does not throw on wrong-typed fields', () {
      final r = UploadResult.fromJson({
        'url': 123,
        'pathname': ['a'],
        'contentType': true,
        'name': 42,
        'size': 'big',
      });
      expect(r.url, '');
      expect(r.pathname, '');
      expect(r.contentType, 'application/octet-stream');
      expect(r.name, '');
      expect(r.size, 0);
    });
  });
}
