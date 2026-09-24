import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/projects/presentation/screens/projects_screen.dart';

void main() {
  group('projectGlyphIcon', () {
    test('a stored NAME maps to a Material icon, never clipped text', () {
      // The list once showed "fol" — the word "folder" in a 36px box — because
      // a name reached a Text widget raw. Names now map to real icons.
      expect(projectGlyphIcon('folder'), Icons.folder_outlined);
      expect(projectGlyphIcon('code'), Icons.code_rounded);
      expect(projectGlyphIcon('research'), Icons.science_outlined);
    });

    test('a known emoji maps to its icon, not a raw glyph', () {
      expect(projectGlyphIcon('🚀'), Icons.rocket_launch_outlined);
      expect(projectGlyphIcon('💻'), Icons.code_rounded);
    });

    test('an unknown name or emoji falls back to a folder', () {
      expect(projectGlyphIcon('whatever-this-is'), Icons.folder_outlined);
      expect(projectGlyphIcon('🎯'), Icons.folder_outlined);
    });

    test('empty and null fall back', () {
      expect(projectGlyphIcon(null), Icons.folder_outlined);
      expect(projectGlyphIcon('   '), Icons.folder_outlined);
    });
  });
}
