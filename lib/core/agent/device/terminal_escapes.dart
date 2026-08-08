/// Strips terminal control sequences from PTY output.
///
/// A real shell emits far more than text. Our prompt alone carries an OSC 7
/// sequence (`ESC ] 7 ; <cwd> BEL`) so the session can track `cd` — see
/// `pty_shell.dart` — and without stripping, that payload renders as a stray
/// `:/data/data/…/shell` line above every prompt. Colour codes, cursor moves
/// and title-setting sequences are the same problem in other clothes.
///
/// This matters twice over: the scrollback is both **what the user reads** and
/// **what the model reads** (`ShellScrollback.transcript`). Escape noise in the
/// transcript spends context on bytes that mean nothing to the model and can
/// make it misread output — so it is stripped once, on the way in, rather than
/// at render time.
///
/// Deliberately a stripper, not a terminal emulator. Rendering colour and
/// cursor addressing properly needs a real grid emulator, which is a much
/// bigger thing (`docs/shell/09-T3CODE-TEARDOWN.md` §3 reaches the same
/// conclusion). Until then, readable plain text beats a screen of `[0;32m`.
library;

const int _esc = 0x1b;
const int _bel = 0x07;

/// Matches the erase-display sequences `clear` and `reset` emit:
/// `ESC[2J` (whole screen), `ESC[3J` (screen + scrollback), `ESC[H` combined.
///
/// Exposed because a scrollback list has no grid to erase — the sequence has
/// to be turned into an action ([ShellScrollback.clear]) rather than stripped
/// as noise, which is why `clear` previously did nothing at all.
///
/// **Only 2 and 3.** This was `[0-3]?J`, which also matched `ESC[J`, `ESC[0J`
/// (erase from the cursor to the end of the screen) and `ESC[1J` (erase to the
/// cursor). Those are not "the user cleared the screen" — a shell emits them
/// routinely while redrawing its prompt and editing a line, several times per
/// command. Every one of them wiped the model's transcript.
///
/// That is the whole of the long-running "the agent cannot see my terminal"
/// bug. Measured on device 2026-08-05: typing one `echo` and asking about it
/// produced `erase-display cleared 2 lines`, then `7 lines`, then `1 lines`,
/// and the send that followed read `lines=0` — while the screen still plainly
/// showed the output, because xterm has a grid and applies a partial erase
/// correctly.
///
/// A partial erase is defined relative to a cursor. A flat list of lines has
/// no cursor, so there is no honest way to apply one — leaving the transcript
/// alone is right, and the sequence is stripped as noise like any other.
final RegExp eraseDisplayPattern = RegExp(r'\x1b\[[23]J');

/// Index just past the LAST erase-display sequence, or -1 if there is none.
///
/// The index matters: `clear` sends the erase and then the shell reprints its
/// prompt in the same chunk. Clearing and then appending the whole chunk would
/// resurrect the text that was just erased, so callers keep only what follows.
int lastEraseDisplayEnd(String input) {
  if (!input.contains('\x1b')) return -1;
  var end = -1;
  for (final m in eraseDisplayPattern.allMatches(input)) {
    end = m.end;
  }
  return end;
}

/// Removes ANSI/OSC escape sequences and stray carriage returns.
///
/// Keeps `\n` and `\t` — they carry layout the reader needs.
String stripTerminalEscapes(String input) {
  if (!input.contains('\x1b') &&
      !input.contains('\r') &&
      !input.contains('\x07')) {
    // Overwhelmingly the common case for ordinary command output; don't pay
    // for a scan-and-rebuild on every chunk of a large `cat`.
    return input;
  }

  final out = StringBuffer();
  final units = input.codeUnits;
  var i = 0;

  while (i < units.length) {
    final c = units[i];

    if (c == _esc) {
      // A chunk can end mid-sequence — PTY output is split at arbitrary byte
      // boundaries. Drop the orphan rather than emitting a literal ESC, which
      // would render as a control glyph.
      if (i + 1 >= units.length) break;
      final next = units[i + 1];

      // CSI — ESC [ params… final(@..~). Colours, cursor movement, erase.
      if (next == 0x5b /* [ */) {
        i += 2;
        while (i < units.length && (units[i] < 0x40 || units[i] > 0x7e)) {
          i++;
        }
        i++; // consume the final byte
        continue;
      }

      // OSC — ESC ] … terminated by BEL or ST (ESC \). This is the one that
      // carries our cwd reporting, and the one that leaked into the UI.
      if (next == 0x5d /* ] */) {
        i += 2;
        while (i < units.length) {
          if (units[i] == _bel) {
            i++;
            break;
          }
          if (units[i] == _esc &&
              i + 1 < units.length &&
              units[i + 1] == 0x5c /* \ */) {
            i += 2;
            break;
          }
          i++;
        }
        continue;
      }

      // Anything else is a two-byte escape (ESC =, ESC >, charset selects…).
      i += 2;
      continue;
    }

    if (c == _bel) {
      i++;
      continue;
    }

    if (c == 0x0d /* \r */) {
      // CRLF → LF; a lone CR is a line-overwrite we can't honour without a
      // grid, and leaving it in makes text render on top of itself.
      if (i + 1 < units.length && units[i + 1] == 0x0a) {
        out.writeCharCode(0x0a);
        i += 2;
      } else {
        i++;
      }
      continue;
    }

    out.writeCharCode(c);
    i++;
  }

  return out.toString();
}
