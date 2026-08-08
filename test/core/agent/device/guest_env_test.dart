import 'package:flutter_test/flutter_test.dart';

/// Host paths must never reach a guest rootfs.
///
/// The failure this guards is total, not cosmetic: with Android's PATH inside
/// Kali, /etc/profile cannot run `id`, its root test fails, and PATH is never
/// set — so nothing resolves for the rest of the session.
Map<String, String> hostOnlyStripped(Map<String, String> env) {
  const hostOnly = {'PATH', 'PREFIX', 'LD_LIBRARY_PATH'};
  return {
    for (final e in env.entries)
      if (!hostOnly.contains(e.key)) e.key: e.value,
  };
}

void main() {
  test('drops the three vars that describe a host filesystem', () {
    final out = hostOnlyStripped({
      'PATH': '/data/app/prefix/bin:/system/bin',
      'PREFIX': '/data/app/prefix',
      'LD_LIBRARY_PATH': '/data/app/prefix/lib',
    });
    expect(out, isEmpty);
  });

  test('keeps everything else untouched', () {
    final out = hostOnlyStripped({
      'PATH': '/system/bin',
      'CN_SESSION': 'shell-1',
      'EDITOR': 'nano',
      'HOME': '/root',
    });
    expect(out, {
      'CN_SESSION': 'shell-1',
      'EDITOR': 'nano',
      'HOME': '/root',
    });
  });

  test('an empty env stays empty rather than throwing', () {
    expect(hostOnlyStripped(const {}), isEmpty);
  });

  test('is case-sensitive, as POSIX env vars are', () {
    // `Path` is a different variable from `PATH` and must survive.
    final out = hostOnlyStripped({'Path': 'x', 'PATH': 'y'});
    expect(out, {'Path': 'x'});
  });
}
