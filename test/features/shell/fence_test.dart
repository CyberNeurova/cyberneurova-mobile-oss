import 'package:cyberneurova_mobile/features/shell/presentation/widgets/fence.dart';
import 'package:flutter_test/flutter_test.dart';

/// The failure this guards against is quiet: mis-splitting drops the FIRST
/// line of a command block, and the user only finds out when the thing they
/// pasted does not work.
void main() {
  test('takes the language tag off a tagged fence', () {
    final (lang, body) = splitFence('bash\nls -la\ncd /root');
    expect(lang, 'bash');
    expect(body, 'ls -la\ncd /root');
  });

  test('lowercases the tag', () {
    expect(splitFence('Bash\necho hi').$1, 'bash');
    expect(splitFence('JSON\n{}').$1, 'json');
  });

  test('keeps every line when there is NO tag', () {
    // The dangerous case. `apk add nmap` is a plausible first line and must
    // not be mistaken for a language.
    final (lang, body) = splitFence('apk add nmap\napk add git');
    expect(lang, isNull);
    expect(body, 'apk add nmap\napk add git');
  });

  test('a single line with no newline is all body', () {
    final (lang, body) = splitFence('ls -la');
    expect(lang, isNull);
    expect(body, 'ls -la');
  });

  test('a leading newline (bare ``` fence) is not treated as a tag', () {
    final (lang, body) = splitFence('\nls -la\npwd');
    expect(lang, isNull);
    expect(body, 'ls -la\npwd');
  });

  test('accepts the punctuation real tags use', () {
    for (final t in ['c++', 'objective-c', 'f#', 'shell_session', 'py3']) {
      expect(splitFence('$t\nbody').$1, t.toLowerCase(), reason: t);
    }
  });

  test('rejects a long first line as a tag', () {
    // No language is 17+ characters; a line that long is content.
    const long = 'averyverylongword12345';
    final (lang, body) = splitFence('$long\nrest');
    expect(lang, isNull);
    expect(body, '$long\nrest');
  });

  test('rejects a first line containing spaces', () {
    final (lang, body) = splitFence('rm -rf build\necho done');
    expect(lang, isNull);
    expect(body, 'rm -rf build\necho done');
  });

  test('trims trailing whitespace but keeps interior blank lines', () {
    final (_, body) = splitFence('bash\nline1\n\nline3\n\n');
    expect(body, 'line1\n\nline3');
  });

  test('an empty body stays empty rather than throwing', () {
    expect(splitFence('bash\n').$2, '');
    expect(splitFence('').$2, '');
  });
}
