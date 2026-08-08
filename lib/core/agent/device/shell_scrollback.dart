import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Who produced a line of scrollback.
///
/// This is the distinction that makes the workspace feel like pair-work
/// rather than two tools sharing a screen — `docs/shell/07-REPO-STRUCTURE.md`
/// calls for a `gutter_marker.dart` precisely so the user can always tell
/// what the agent did from what they typed.
enum ShellLineSource {
  /// The human typed it into the terminal.
  user,

  /// The agent issued it via a tool call.
  agent,

  /// The app said it — session started, process exited, tool refused.
  system,
}

class ShellLine {
  const ShellLine(this.text, this.source, this.at, {this.isCommand = false});

  final String text;
  final ShellLineSource source;
  final DateTime at;

  /// True for the command itself, false for its output. Lets a renderer
  /// echo `$ ls -la` differently from the listing it produced, and lets the
  /// model-facing transcript stay readable.
  final bool isCommand;
}

/// The ONE scrollback a shell workspace has.
///
/// `docs/shell/00-OVERVIEW.md` §1: *"the terminal and the agent share one
/// session, one working directory, one environment, one scrollback."* The cwd
/// and env live in `ShellSession`; this is the scrollback half.
///
/// Two things depend on it being shared:
///
/// 1. **The user sees the agent work.** Commands the agent runs land in the
///    same buffer the user is reading, in order, marked as agent-issued.
/// 2. **The agent sees the user work.** [transcript] renders recent history
///    for the model, so if the user typed `cd /opt && ls` by hand, the agent's
///    next turn knows it. Without this the agent is blind to half the session
///    and gives advice about a state that no longer exists — the thing that
///    makes most "AI terminal" tools feel disconnected.
///
/// Bounded on purpose: `01-ANDROID-RUNTIME.md` §5 notes unbounded scrollback
/// is the most common OOM in terminal apps.
class ShellScrollback {
  ShellScrollback({this.maxLines = 5000});

  final int maxLines;
  final ListQueue<ShellLine> _lines = ListQueue<ShellLine>();
  final _controller = StreamController<ShellLine>.broadcast();

  /// Fires per appended line so a renderer can append incrementally instead
  /// of rebuilding the whole buffer.
  Stream<ShellLine> get stream => _controller.stream;

  /// Bumps once per append.
  ///
  /// UI binds to this rather than to [stream] so a burst of output repaints
  /// the list **without** rebuilding the widget tree per line —
  /// `docs/shell/09-T3CODE-TEARDOWN.md` §2.2: terminal output arrives in
  /// bursts of thousands of lines/sec, and routing each one through the
  /// framework's rebuild path is what makes mobile terminals drop frames.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<ShellLine> get lines => List.unmodifiable(_lines);

  int get length => _lines.length;

  bool get isEmpty => _lines.isEmpty;

  /// True when the last line is an unterminated PTY chunk still being written.
  bool _openTail = false;

  /// Appends a chunk of **streamed** output, respecting line boundaries.
  ///
  /// A PTY hands you bytes whenever the kernel has them, split at arbitrary
  /// points — `uname -a` came back as `un` then `ame -a` on a real device, and
  /// [append] rendered that as two lines. Terminal output is only a line when
  /// it contains `\n`, so a chunk that doesn't end in one leaves its tail open
  /// for the next chunk to continue.
  ///
  /// Use this for anything read off a process. [append] stays the right call
  /// for a complete, already-bounded string (a tool result, a system notice).
  void appendStream(String chunk, {required ShellLineSource source}) {
    if (chunk.isEmpty) return;

    final parts = chunk.split('\n');
    // `"abc\n".split` yields a trailing '' that is the *terminator*, not a
    // blank line. Interior blanks are real and must survive.
    if (parts.length > 1 && parts.last.isEmpty) parts.removeLast();

    for (var i = 0; i < parts.length; i++) {
      final continues =
          i == 0 && _openTail && _lines.isNotEmpty && _lines.last.source == source;
      if (continues) {
        final prev = _lines.removeLast();
        _lines.addLast(ShellLine(prev.text + parts[i], prev.source, prev.at,
            isCommand: prev.isCommand));
      } else {
        final line = ShellLine(parts[i], source, DateTime.now());
        _lines.addLast(line);
        if (!_controller.isClosed) _controller.add(line);
      }
    }

    _openTail = !chunk.endsWith('\n');
    _trim();
    revision.value++;
  }

  void append(
    String text, {
    required ShellLineSource source,
    bool isCommand = false,
    DateTime? at,
  }) {
    // A discrete message never continues a half-written PTY line — gluing a
    // system notice onto the tail of somebody's output would misattribute it.
    _openTail = false;
    // Split on newlines so the buffer is genuinely line-addressable — a tool
    // that writes a 40-line result in one call must not become one "line"
    // that trimming then evicts wholesale.
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      // Drop a single trailing empty piece (from text ending in \n) but keep
      // interior blank lines, which are meaningful in command output.
      if (i == parts.length - 1 && parts[i].isEmpty && parts.length > 1) break;
      final line = ShellLine(
        parts[i],
        source,
        at ?? DateTime.now(),
        isCommand: isCommand && i == 0,
      );
      _lines.addLast(line);
      if (!_controller.isClosed) _controller.add(line);
    }
    _trim();
    // Once per append, not per line: a 40-line tool result is one repaint.
    revision.value++;
  }

  void _trim() {
    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }
  }

  /// Empties the buffer — what `clear` is supposed to do.
  ///
  /// A real terminal clears by moving the cursor and erasing the grid, which
  /// only works if you HAVE a grid. We render a scrollback list instead, so
  /// the erase sequence was stripped along with the other escapes and `clear`
  /// silently did nothing. The pane watches for the sequence and calls this.
  void clear() {
    _lines.clear();
    _openTail = false;
    revision.value++;
  }

  /// Convenience for the two common shapes.
  void appendCommand(String command, {required ShellLineSource source}) =>
      append(command, source: source, isCommand: true);

  void appendSystem(String text) =>
      append(text, source: ShellLineSource.system);

  /// Renders recent scrollback for the model.
  ///
  /// Marked up by source so the agent can tell its own past actions from the
  /// user's — without that it re-runs things the user already ran, or claims
  /// credit for output it didn't produce. [maxLines] and [maxChars] keep a
  /// noisy session from eating the context window; the TAIL is kept because
  /// the recent state is what matters in a shell.
  String transcript({int maxLines = 200, int maxChars = 6000}) {
    final take = _lines.length <= maxLines
        ? _lines.toList()
        : _lines.toList().sublist(_lines.length - maxLines);

    final buf = StringBuffer();
    for (final l in take) {
      final marker = switch (l.source) {
        ShellLineSource.user => l.isCommand ? '\$ ' : '  ',
        ShellLineSource.agent => l.isCommand ? '[agent] \$ ' : '  ',
        ShellLineSource.system => '# ',
      };
      buf.writeln('$marker${l.text}');
    }

    var out = buf.toString();
    if (out.length > maxChars) {
      // Trim from the front, and say so — silently truncating history makes
      // the model reason confidently about a session it can't fully see.
      out = '…(earlier output trimmed)…\n'
          '${out.substring(out.length - maxChars)}';
    }
    return out;
  }

  Future<void> dispose() async {
    revision.dispose();
    if (!_controller.isClosed) await _controller.close();
  }
}
