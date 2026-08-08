import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resolving a stored preference against what is actually on disk. The rule
/// that matters: a stale preference must never stop the Console opening.
Distro? resolve({
  required String? preferred,
  required Set<String> installed,
}) {
  if (preferred != null) {
    for (final d in kDistroCatalog) {
      if (d.id == preferred && installed.contains(d.id)) return d;
    }
  }
  for (final d in kDistroCatalog) {
    if (installed.contains(d.id)) return d;
  }
  return null;
}

void main() {
  test('the preference wins when that distro is installed', () {
    final d = resolve(preferred: 'kali', installed: {'alpine', 'kali'});
    expect(d?.id, 'kali');
  });

  test('a stale preference falls back instead of failing', () {
    // User picked Kali, then removed it. The Console must still open.
    final d = resolve(preferred: 'kali', installed: {'alpine'});
    expect(d?.id, 'alpine');
  });

  test('no preference takes the first installed in catalogue order', () {
    expect(resolve(preferred: null, installed: {'kali', 'alpine'})?.id,
        'alpine');
  });

  test('nothing installed means the Android shell, not a crash', () {
    expect(resolve(preferred: 'kali', installed: const {}), isNull);
    expect(resolve(preferred: null, installed: const {}), isNull);
  });

  test('a preference naming a distro that does not exist is ignored', () {
    // A catalogue entry could be withdrawn in a later release.
    final d = resolve(preferred: 'gentoo', installed: {'alpine'});
    expect(d?.id, 'alpine');
  });

  test('preferring the only installed distro is stable', () {
    expect(resolve(preferred: 'alpine', installed: {'alpine'})?.id, 'alpine');
  });
}
