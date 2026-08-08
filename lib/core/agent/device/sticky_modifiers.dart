import 'package:flutter/foundation.dart';

/// Ctrl and Alt held for exactly one keystroke.
///
/// ## Why this is not just state inside the key row
///
/// A phone keyboard has no Ctrl, so the extra-keys row offers a sticky one:
/// tap `ctrl`, then the next key is sent as a chord. That worked only for keys
/// **in the row** — Esc, Tab, arrows — because those are the only ones that
/// passed through its send path.
///
/// A letter typed on the soft keyboard goes straight into the terminal grid
/// and never touches the row. So `ctrl` then `x` sent a plain `x`, and there
/// was no way to press Ctrl+X, Ctrl+C or Ctrl+D at all: nano, vim and less
/// could be opened and never left.
///
/// Holding the armed state here, where the terminal's write path can also
/// read it, is what makes the chord work regardless of which keyboard the
/// character came from.
class StickyModifiers extends ChangeNotifier {
  bool _ctrl = false;
  bool _alt = false;

  bool get ctrl => _ctrl;
  bool get alt => _alt;
  bool get any => _ctrl || _alt;

  void toggleCtrl() {
    _ctrl = !_ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    _alt = !_alt;
    notifyListeners();
  }

  void clear() {
    if (!any) return;
    _ctrl = false;
    _alt = false;
    notifyListeners();
  }

  /// Applies any armed modifier to [input] and disarms.
  ///
  /// Called from the terminal's write path, so it sees every keystroke —
  /// including ones typed on the system keyboard.
  String consume(String input) {
    if (!any || input.isEmpty) return input;
    var out = input;
    if (_ctrl) out = applyCtrl(out);
    if (_alt) out = '\x1b$out';
    clear();
    return out;
  }

  /// Ctrl-maps a character the way a terminal does: ctrl-a → 0x01.
  ///
  /// Only the FIRST character is mapped. A soft keyboard can deliver several
  /// at once (autocomplete, paste), and turning a whole word into control
  /// codes would be nonsense — a chord is one key.
  static String applyCtrl(String input) {
    if (input.isEmpty) return input;
    final first = input[0];
    final rest = input.substring(1);
    final lower = first.toLowerCase();
    if (lower.compareTo('a') >= 0 && lower.compareTo('z') <= 0) {
      return String.fromCharCode(lower.codeUnitAt(0) - 96) + rest;
    }
    final mapped = switch (first) {
      '@' => '\x00',
      '[' => '\x1b',
      '\\' => '\x1c',
      ']' => '\x1d',
      '^' => '\x1e',
      '_' => '\x1f',
      '?' => '\x7f',
      ' ' => '\x00',
      _ => null,
    };
    return mapped == null ? input : mapped + rest;
  }
}
