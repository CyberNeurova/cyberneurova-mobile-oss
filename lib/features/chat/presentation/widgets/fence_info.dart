/// The opening fence's info string, split into what we can use.
///
/// `html`, `html:clock.html`, `dart title=main.dart`, `js // app.js` — the
/// first word is the language and anything that looks like a file name is the
/// name the model intended for this block. Both are hints: a fence carrying
/// neither still renders.
///
/// Extracted from the bubble so it can be tested directly. The fence regex it
/// serves used to reject a dot or a colon in the info string, which meant a
/// ```` ```html:clock.html ```` block did not match as a fence at all and fell
/// through to markdown as raw text — the one case where the model tells us
/// what the file should be called was the one case that could not be read.
class FenceInfo {
  const FenceInfo(this.language, this.filename);
  final String? language;
  final String? filename;

  // The extension must START with a letter, or `python3.11` reads as a file
  // called "python3" with extension "11" and the block offers to save itself
  // under the interpreter's version number.
  static final _nameRe = RegExp(r'^[\w.\-]+\.[A-Za-z][A-Za-z0-9]{0,7}$');

  static FenceInfo parse(String? raw) {
    final info = (raw ?? '').trim();
    if (info.isEmpty) return const FenceInfo(null, null);
    final parts = info
        .split(RegExp(r'[\s:=,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '//' && s != '#')
        .toList();
    if (parts.isEmpty) return const FenceInfo(null, null);
    String? name;
    for (final part in parts) {
      final leaf = part.split('/').last;
      if (_nameRe.hasMatch(leaf)) {
        name = leaf;
        break;
      }
    }
    // A bare `clock.html` fence names the file, not the language.
    final first = parts.first;
    final lang = (name != null && first == name) ? name.split('.').last : first;
    return FenceInfo(lang.isEmpty ? null : lang, name);
  }
}

/// A sensible file extension for a fence that only told us its language.
String extensionForLanguage(String? l) {
  final lower = (l ?? '').toLowerCase();
  return switch (lower) {
    'javascript' || 'js' || 'node' => 'js',
    'typescript' || 'ts' => 'ts',
    'python' || 'py' => 'py',
    'bash' || 'sh' || 'shell' || 'zsh' => 'sh',
    'yaml' || 'yml' => 'yaml',
    'kotlin' || 'kt' => 'kt',
    'rust' || 'rs' => 'rs',
    'ruby' || 'rb' => 'rb',
    'markdown' || 'md' => 'md',
    'html' ||
    'css' ||
    'json' ||
    'dart' ||
    'java' ||
    'go' ||
    'sql' ||
    'xml' ||
    'c' ||
    'cpp' ||
    'php' ||
    'swift' =>
      lower,
    _ => 'txt',
  };
}
