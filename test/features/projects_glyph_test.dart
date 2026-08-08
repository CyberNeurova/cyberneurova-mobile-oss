import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/projects/presentation/screens/projects_screen.dart';

void main() {
  group('projectGlyph', () {
    test('a stored NAME becomes a glyph, not clipped text', () {
      // The list showed "fol" — the word "folder" in a 36px box.
      expect(projectGlyph('folder'), '📁');
      expect(projectGlyph('code'), '💻');
      expect(projectGlyph('research'), '🧪');
    });

    test('an unknown name still gets something sane', () {
      expect(projectGlyph('whatever-this-is'), '📁');
    });

    test('an emoji passes through untouched', () {
      expect(projectGlyph('🚀'), '🚀');
      expect(projectGlyph('🎯'), '🎯');
    });

    test('empty and null fall back', () {
      expect(projectGlyph(null), '📁');
      expect(projectGlyph('   '), '📁');
    });
  });
}
