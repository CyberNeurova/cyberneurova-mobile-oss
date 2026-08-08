import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/images/data/models/image_model.dart';

// Sahachiel: ImageGenerateResponse.fromJson hand-parses the synchronous
// /images/generate response. It used to do `images.first as Map` and
// `url as String`, which throw a CastError - and crash the generate flow - on a
// malformed or drifted server payload (images:[null], a bare string, etc.).
// These lock the defensive parsing.
void main() {
  group('ImageGenerateResponse.fromJson', () {
    test('promotes the first image url on a valid payload', () {
      final r = ImageGenerateResponse.fromJson({
        'success': true,
        'images': [
          {'url': 'https://cdn.example.com/a.png'},
        ],
        'text': 'done',
      });
      expect(r.url, 'https://cdn.example.com/a.png');
      expect(r.success, isTrue);
      expect(r.text, 'done');
    });

    test('does not throw when the first image is null', () {
      expect(
        () => ImageGenerateResponse.fromJson({
          'images': [null],
        }),
        returnsNormally,
      );
    });

    test('does not throw when the first image is a bare string', () {
      expect(
        () => ImageGenerateResponse.fromJson({
          'images': ['https://x/y.png'],
        }),
        returnsNormally,
      );
    });

    test('does not throw on an empty or missing images list', () {
      expect(
        () => ImageGenerateResponse.fromJson({'images': <dynamic>[]}),
        returnsNormally,
      );
      expect(
        () => ImageGenerateResponse.fromJson(<String, dynamic>{}),
        returnsNormally,
      );
    });

    test('tolerates wrong-typed success / text / usage fields', () {
      final r = ImageGenerateResponse.fromJson({
        'success': 'true', // String, not bool
        'text': 42, // not a String
        'usage': 'nope', // not a Map
        'images': [
          {'url': 'https://x/y.png'},
        ],
      });
      expect(r.success, isTrue); // falls back to the default
      expect(r.text, isNull);
      expect(r.usage, isNull);
      expect(r.url, 'https://x/y.png');
    });

    test('parses a valid usage block', () {
      final r = ImageGenerateResponse.fromJson({
        'images': [
          {'url': 'https://x/y.png'},
        ],
        'usage': {'used': 3, 'limit': 10, 'remaining': 7},
      });
      expect(r.usage, isNotNull);
      expect(r.usage!.remaining, 7);
    });
  });
}
