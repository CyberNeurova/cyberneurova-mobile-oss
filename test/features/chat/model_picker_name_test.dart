import 'package:cyberneurova_mobile/features/chat/presentation/widgets/model_picker.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chip in the Console app bar is narrow enough to ellipsize, and every
/// model shares the same brand prefix — so keeping the prefix is the one
/// choice guaranteed to show nothing useful.
void main() {
  test('drops the brand prefix so the discriminator survives', () {
    expect(shortModelName('CyberNeurova Gemma'), 'Gemma');
    expect(shortModelName('CyberNeurova GLM 5.2'), 'GLM 5.2');
    expect(shortModelName('CyberNeurova Kimi 2.7 Code'), 'Kimi 2.7 Code');
  });

  test('leaves names without the prefix alone', () {
    expect(shortModelName('Tiny Neurova'), 'Tiny Neurova');
    expect(shortModelName('Model'), 'Model');
    expect(shortModelName('Loading…'), 'Loading…');
  });

  test('does not return empty for the bare prefix', () {
    // A name that is exactly the prefix would otherwise render as a blank
    // chip — worse than showing the redundant text.
    expect(shortModelName('CyberNeurova '), 'CyberNeurova ');
    expect(shortModelName('CyberNeurova'), 'CyberNeurova');
  });

  test('is not fooled by a lowercase or partial match', () {
    expect(shortModelName('cyberneurova Gemma'), 'cyberneurova Gemma');
    expect(shortModelName('CyberNeurovaGemma'), 'CyberNeurovaGemma');
  });
}
