import 'package:cyberneurova_mobile/core/agent/device/terminal_escapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripTerminalEscapes', () {
    test('leaves plain text untouched', () {
      expect(stripTerminalEscapes('hello world\n'), 'hello world\n');
    });

    test('removes SGR colour codes but keeps the text', () {
      expect(
        stripTerminalEscapes('\x1b[0;32mgreen\x1b[0m plain'),
        'green plain',
      );
    });

    test('removes the OSC 7 cwd report our own prompt emits', () {
      // Measured on device: this leaked as a bare `:/data/…/shell` line above
      // every prompt. PS1 is r'\[\e]7;\w\a\]$ ' — see pty_shell.dart.
      const raw = '\x1b]7;/data/data/ai.cyberneurova.app/app_flutter/shell\x07'
          '\$ ';
      expect(stripTerminalEscapes(raw), '\$ ');
    });

    test('handles OSC terminated by ST instead of BEL', () {
      expect(stripTerminalEscapes('\x1b]0;window title\x1b\\text'), 'text');
    });

    test('removes cursor movement and erase sequences', () {
      expect(stripTerminalEscapes('a\x1b[2J\x1b[Hb'), 'ab');
    });

    test('removes two-byte escapes', () {
      expect(stripTerminalEscapes('\x1b=on\x1b>off'), 'onoff');
    });

    test('collapses CRLF to LF and drops a lone CR', () {
      expect(stripTerminalEscapes('one\r\ntwo\rthree'), 'one\ntwothree');
    });

    test('keeps tabs — they carry column layout', () {
      expect(stripTerminalEscapes('a\tb'), 'a\tb');
    });

    test('drops a bare BEL', () {
      expect(stripTerminalEscapes('ding\x07dong'), 'dingdong');
    });

    test('does not hang on a truncated sequence at end of chunk', () {
      // PTY output arrives in arbitrary chunks, so a sequence can be cut in
      // half. Dropping the tail is acceptable; looping forever is not.
      expect(stripTerminalEscapes('text\x1b['), 'text');
      expect(stripTerminalEscapes('text\x1b]7;/partial'), 'text');
      expect(stripTerminalEscapes('text\x1b'), 'text');
    });

    test('returns the same instance when there is nothing to strip', () {
      const input = 'a large amount of ordinary command output';
      expect(identical(stripTerminalEscapes(input), input), isTrue);
    });
  });

  group('lastEraseDisplayEnd', () {
    // A hit here means "the user cleared the screen", and the caller throws
    // away the model's whole transcript. Getting it wrong is expensive and was:
    // the pattern used to accept ESC[J / ESC[0J / ESC[1J, which a shell emits
    // while redrawing its prompt, so the transcript was wiped several times per
    // command and the agent could never see the terminal.

    test('a real clear erases: ESC[2J and ESC[3J', () {
      expect(lastEraseDisplayEnd('\x1b[2J'), greaterThan(-1));
      expect(lastEraseDisplayEnd('\x1b[3J'), greaterThan(-1));
      // What `clear` actually sends: erase, then reposition, then the prompt.
      // Assert on what the caller keeps rather than the raw index — that is
      // the property the scrollback depends on.
      const cleared = '\x1b[H\x1b[2J\x1b[3Jhost:~# ';
      expect(cleared.substring(lastEraseDisplayEnd(cleared)), 'host:~# ');
    });

    test('a PARTIAL erase does NOT erase the transcript', () {
      // Erase-below (the prompt-redraw one), erase-above, and the bare form
      // that defaults to erase-below.
      for (final seq in ['\x1b[J', '\x1b[0J', '\x1b[1J']) {
        expect(lastEraseDisplayEnd(seq), -1, reason: seq);
      }
    });

    test('prompt redraw around real output keeps the output', () {
      // Shape observed from the device's ash prompt.
      const chunk = 'ZEBRA_MARKER_7788\n\x1b[0Klocalhost:~# \x1b[J';
      expect(lastEraseDisplayEnd(chunk), -1);
    });

    test('the LAST erase wins, so nothing erased is resurrected', () {
      const chunk = '\x1b[2Jold\x1b[2Jkept';
      final end = lastEraseDisplayEnd(chunk);
      expect(chunk.substring(end), 'kept');
    });

    test('text with no escapes at all is never a clear', () {
      expect(lastEraseDisplayEnd('total 0\nfoo.txt'), -1);
    });

    test('a partial erase is still stripped as noise', () {
      // It must not clear the transcript AND must not leak into it.
      expect(stripTerminalEscapes('a\x1b[0Jb'), 'ab');
    });
  });
}
