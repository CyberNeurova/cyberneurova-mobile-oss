import 'package:cyberneurova_mobile/core/agent/device/sticky_modifiers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Without a working Ctrl there is no way out of nano, vim or less — the
/// editor opens and the session is stuck. That is the failure these guard.
void main() {
  test('ctrl maps letters to control codes', () {
    expect(StickyModifiers.applyCtrl('x'), '\x18'); // Ctrl+X, nano exit
    expect(StickyModifiers.applyCtrl('c'), '\x03'); // Ctrl+C, interrupt
    expect(StickyModifiers.applyCtrl('d'), '\x04'); // Ctrl+D, EOF
    expect(StickyModifiers.applyCtrl('a'), '\x01');
    expect(StickyModifiers.applyCtrl('z'), '\x1a');
  });

  test('case does not matter — Ctrl+X and Ctrl+x are the same chord', () {
    expect(StickyModifiers.applyCtrl('X'), StickyModifiers.applyCtrl('x'));
  });

  test('the punctuation chords a terminal defines', () {
    expect(StickyModifiers.applyCtrl('['), '\x1b'); // Ctrl+[ is Escape
    expect(StickyModifiers.applyCtrl('?'), '\x7f');
    expect(StickyModifiers.applyCtrl('@'), '\x00');
  });

  test('only the FIRST character is mapped', () {
    // A soft keyboard can deliver a whole word at once (autocomplete, paste).
    // Turning all of it into control codes would be nonsense — a chord is one
    // key, and the rest is ordinary text.
    expect(StickyModifiers.applyCtrl('xyz'), '\x18yz');
  });

  test('an unmappable character is left alone', () {
    expect(StickyModifiers.applyCtrl('1'), '1');
    expect(StickyModifiers.applyCtrl(''), '');
  });

  test('consume applies the armed modifier and disarms', () {
    final m = StickyModifiers()..toggleCtrl();
    expect(m.ctrl, isTrue);
    expect(m.consume('x'), '\x18');
    expect(m.ctrl, isFalse, reason: 'sticky means one keystroke, not a lock');
  });

  test('consume is a no-op when nothing is armed', () {
    final m = StickyModifiers();
    expect(m.consume('x'), 'x');
  });

  test('alt prefixes escape, as a terminal expects', () {
    final m = StickyModifiers()..toggleAlt();
    expect(m.consume('f'), '\x1bf');
  });

  test('ctrl and alt together compose', () {
    final m = StickyModifiers()
      ..toggleCtrl()
      ..toggleAlt();
    expect(m.consume('c'), '\x1b\x03');
    expect(m.any, isFalse);
  });

  test('notifies so the armed state can be shown', () {
    final m = StickyModifiers();
    var n = 0;
    m.addListener(() => n++);
    m.toggleCtrl();
    m.consume('x');
    expect(n, 2, reason: 'one for arming, one for disarming');
  });
}
