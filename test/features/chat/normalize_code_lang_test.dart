import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/code_panel.dart';

/// Fence languages and file extensions, mapped to what the highlighter knows.
///
/// Two callers with different inputs share this. Chat passes a fence label
/// (```py), and the file viewer passes a bare file EXTENSION stripped of its
/// dot — which is why the lower-casing matters more than it looks: `README.MD`
/// and `Main.KT` are ordinary filenames, and an uppercase extension that missed
/// the alias table would render as unhighlighted plain text with no clue why.
void main() {
  group('aliases reach the highlighter under its own names', () {
    test('the short forms people actually type', () {
      expect(normalizeCodeLang('js'), 'javascript');
      expect(normalizeCodeLang('ts'), 'typescript');
      expect(normalizeCodeLang('tsx'), 'typescript');
      expect(normalizeCodeLang('py'), 'python');
      expect(normalizeCodeLang('yml'), 'yaml');
      expect(normalizeCodeLang('kt'), 'kotlin');
      expect(normalizeCodeLang('rs'), 'rust');
      expect(normalizeCodeLang('rb'), 'ruby');
      expect(normalizeCodeLang('md'), 'markdown');
    });

    test('every shell name lands on bash', () {
      for (final s in ['sh', 'shell', 'zsh']) {
        expect(normalizeCodeLang(s), 'bash', reason: s);
      }
    });

    test('case is irrelevant, which is what the file viewer relies on', () {
      // It calls this with `ext.substring(1)` — so `.PY` arrives as `PY`.
      expect(normalizeCodeLang('PY'), 'python');
      expect(normalizeCodeLang('Md'), 'markdown');
      expect(normalizeCodeLang('YML'), 'yaml');
    });
  });

  group('everything else', () {
    test('a name the highlighter already knows passes through', () {
      expect(normalizeCodeLang('python'), 'python');
      expect(normalizeCodeLang('dart'), 'dart');
      expect(normalizeCodeLang('JSON'), 'json');
    });

    test('an unknown language is passed on lowercased, not discarded', () {
      // Better to hand the highlighter something it may know than to force
      // plaintext on every language this switch has not heard of.
      expect(normalizeCodeLang('zig'), 'zig');
      expect(normalizeCodeLang('Nim'), 'nim');
    });

    test('nothing at all means plaintext', () {
      expect(normalizeCodeLang(null), 'plaintext');
      expect(normalizeCodeLang(''), 'plaintext');
    });
  });
}
