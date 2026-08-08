import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/images/data/image_downloader.dart';

void main() {
  group('galleryFileName', () {
    test('leads with the prompt, because that is what the user remembers', () {
      expect(
        galleryFileName(
            prompt: 'A red wooden sailboat', id: 'abcdef12345678'),
        'a-red-wooden-sailboat-12345678',
      );
    });

    test('produces a safe filename from an awkward prompt', () {
      final name = galleryFileName(
        prompt: 'Neon "city" @ night — 50% rain, wet/streets!',
        id: 'id-0000ffff',
      );
      // Nothing a filesystem or MediaStore would object to.
      expect(RegExp(r'^[a-z0-9-]+$').hasMatch(name), isTrue, reason: name);
      expect(name, startsWith('neon-city-night'));
      expect(name, isNot(contains('--')));
    });

    test('never ends or starts with a separator', () {
      for (final p in ['   ', '...', '!!!', 'trailing punctuation...']) {
        final name = galleryFileName(prompt: p, id: 'zz999999');
        expect(name.startsWith('-'), isFalse, reason: p);
        expect(name.endsWith('-'), isFalse, reason: p);
      }
    });

    test('an empty prompt still yields something findable', () {
      expect(galleryFileName(prompt: '', id: 'abcd1234'),
          'cyberneurova-abcd1234');
    });

    test('a long prompt is cut without leaving a dangling separator', () {
      final name = galleryFileName(
        prompt: 'a very long prompt that keeps going and going well past any '
            'reasonable filename length limit for a gallery entry',
        id: 'deadbeef',
      );
      expect(name.length, lessThanOrEqualTo(48 + 1 + 8));
      expect(name, isNot(contains('--')));
      expect(name, endsWith('-deadbeef'));
    });

    test('the same image saved twice yields the same name', () {
      // Idempotent on purpose: re-saving should not litter the gallery.
      final a = galleryFileName(prompt: 'sunset', id: 'aaaa1111');
      final b = galleryFileName(prompt: 'sunset', id: 'aaaa1111');
      expect(a, b);
    });

    test('two different images never collide', () {
      // The bug this replaces: every save was called "image".
      final a = galleryFileName(prompt: 'sunset', id: 'aaaa1111');
      final b = galleryFileName(prompt: 'sunset', id: 'bbbb2222');
      expect(a, isNot(b));
    });
  });
}
