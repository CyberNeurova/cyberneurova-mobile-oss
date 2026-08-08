/// Line diffing for file-edit tool cards.
///
/// The agent writing a file used to report "Wrote 2431 chars → notes.md",
/// which tells you nothing about what changed — the one thing you want to
/// know before trusting it. This produces a unified diff of the write so the
/// card can show it.
///
/// Kept free of Flutter so it can be tested directly, and deliberately modest:
/// this runs on a phone, in the same isolate as the UI, while an agent may be
/// writing files in a loop.
library;

/// A unified diff of [before] → [after].
///
/// Returns an empty string when nothing changed. [contextLines] is the number
/// of unchanged lines kept around each hunk.
///
/// [maxLines] bounds the *output*, not the input: a rewritten 5000-line file
/// produces a diff nobody will read and a card that janks while it lays out.
/// Past the cap the diff is truncated with a trailing count.
String unifiedDiff(
  String before,
  String after, {
  int contextLines = 3,
  int maxLines = 300,
}) {
  if (before == after) return '';

  final a = _splitLines(before);
  final b = _splitLines(after);

  // LCS is O(n*m) in both time and memory. On a phone, against a file an
  // agent just generated, that is a real risk — so above this size say what
  // happened rather than computing it. The threshold is generous enough that
  // ordinary source files never hit it.
  if (a.length * b.length > 2000 * 2000) {
    return '@@ file replaced @@\n'
        '-${a.length} lines\n'
        '+${b.length} lines';
  }

  final ops = _diffOps(a, b);
  return _render(ops, a, b, contextLines, maxLines);
}

/// Whether [text] looks like the output of [unifiedDiff].
///
/// Used by the UI to decide whether to colour it, so it must not fire on an
/// ordinary tool result that happens to start with a dash.
bool looksLikeDiff(String text) {
  if (text.isEmpty) return false;
  for (final line in text.split('\n')) {
    if (line.startsWith('@@')) return true;
  }
  return false;
}

List<String> _splitLines(String s) {
  if (s.isEmpty) return const [];
  final lines = s.split('\n');
  // A trailing newline yields a final empty element that is not a line.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

enum _Op { keep, add, remove }

class _Edit {
  const _Edit(this.op, this.aIndex, this.bIndex);
  final _Op op;
  final int aIndex;
  final int bIndex;
}

/// Classic LCS backtrack. Rows are kept as a single flat list to avoid
/// allocating one list per line.
List<_Edit> _diffOps(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final width = m + 1;
  final lcs = List<int>.filled((n + 1) * width, 0);

  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i * width + j] = a[i] == b[j]
          ? lcs[(i + 1) * width + (j + 1)] + 1
          : (lcs[(i + 1) * width + j] > lcs[i * width + (j + 1)]
              ? lcs[(i + 1) * width + j]
              : lcs[i * width + (j + 1)]);
    }
  }

  final ops = <_Edit>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(_Edit(_Op.keep, i, j));
      i++;
      j++;
    } else if (lcs[(i + 1) * width + j] >= lcs[i * width + (j + 1)]) {
      ops.add(_Edit(_Op.remove, i, j));
      i++;
    } else {
      ops.add(_Edit(_Op.add, i, j));
      j++;
    }
  }
  while (i < n) {
    ops.add(_Edit(_Op.remove, i, j));
    i++;
  }
  while (j < m) {
    ops.add(_Edit(_Op.add, i, j));
    j++;
  }
  return ops;
}

String _render(
  List<_Edit> ops,
  List<String> a,
  List<String> b,
  int contextLines,
  int maxLines,
) {
  // Which ops to emit: every change, plus [contextLines] either side.
  final keep = List<bool>.filled(ops.length, false);
  for (var k = 0; k < ops.length; k++) {
    if (ops[k].op == _Op.keep) continue;
    final lo = (k - contextLines).clamp(0, ops.length - 1);
    final hi = (k + contextLines).clamp(0, ops.length - 1);
    for (var x = lo; x <= hi; x++) {
      keep[x] = true;
    }
  }

  final out = <String>[];
  var truncated = 0;
  var inHunk = false;

  void emit(String line) {
    if (out.length >= maxLines) {
      truncated++;
      return;
    }
    out.add(line);
  }

  for (var k = 0; k < ops.length; k++) {
    if (!keep[k]) {
      inHunk = false;
      continue;
    }
    final e = ops[k];
    if (!inHunk) {
      // 1-based line numbers, matching what every other diff tool prints.
      emit('@@ -${e.aIndex + 1} +${e.bIndex + 1} @@');
      inHunk = true;
    }
    switch (e.op) {
      case _Op.keep:
        emit('  ${a[e.aIndex]}');
      case _Op.remove:
        emit('- ${a[e.aIndex]}');
      case _Op.add:
        emit('+ ${b[e.bIndex]}');
    }
  }

  if (truncated > 0) {
    out.add('@@ $truncated more line${truncated == 1 ? '' : 's'} @@');
  }
  return out.join('\n');
}
