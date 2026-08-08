import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/device/linux/rootfs_installer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rootfs tarballs disagree about shape. Alpine's contains `etc/`, `bin/` at
/// the top; Kali's wraps everything in `kali-arm64/`. Getting this wrong is
/// quiet and expensive: the extract succeeds, 846 MB lands on disk, and the
/// distro is then reported as not installed because `etc` is one level down.
void main() {
  late Directory tmp;
  late RootfsInstaller installer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cn_rootfs_shape');
    installer = RootfsInstaller(
      distrosDir: '${tmp.path}/distros',
      downloadsDir: '${tmp.path}/dl',
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Directory make(String name, List<String> dirs) {
    final root = Directory('${tmp.path}/distros/$name')
      ..createSync(recursive: true);
    for (final d in dirs) {
      Directory('${root.path}/$d').createSync(recursive: true);
    }
    return root;
  }

  test('a wrapped rootfs is lifted to the top', () {
    final root = make('kali', ['kali-arm64/etc', 'kali-arm64/bin']);
    installer.debugFlatten(root);

    expect(Directory('${root.path}/etc').existsSync(), isTrue);
    expect(Directory('${root.path}/bin').existsSync(), isTrue);
    expect(Directory('${root.path}/kali-arm64').existsSync(), isFalse);
  });

  test('an unwrapped rootfs is left exactly as it is', () {
    final root = make('alpine', ['etc', 'bin', 'usr']);
    installer.debugFlatten(root);

    expect(Directory('${root.path}/etc').existsSync(), isTrue);
    expect(Directory('${root.path}/bin').existsSync(), isTrue);
    expect(Directory('${root.path}/usr').existsSync(), isTrue);
  });

  test('file content survives the lift', () {
    final root = make('kali', ['kali-arm64/etc']);
    File('${root.path}/kali-arm64/etc/os-release')
        .writeAsStringSync('ID=kali\n');

    installer.debugFlatten(root);
    expect(File('${root.path}/etc/os-release').readAsStringSync(), 'ID=kali\n');
  });

  test('two top-level entries are not a wrapper', () {
    // Ambiguous: never guess. A tarball with etc/ plus a stray file must not
    // be "flattened" into something else.
    final root = make('x', ['bin', 'usr']);
    installer.debugFlatten(root);

    expect(Directory('${root.path}/bin').existsSync(), isTrue);
    expect(Directory('${root.path}/usr').existsSync(), isTrue);
  });

  test('a single top-level FILE is not a wrapper', () {
    final root = Directory('${tmp.path}/distros/y')..createSync(recursive: true);
    File('${root.path}/README').writeAsStringSync('x');

    installer.debugFlatten(root);
    expect(File('${root.path}/README').existsSync(), isTrue);
  });

  test('a missing directory is handled rather than thrown', () {
    expect(
      () => installer.debugFlatten(Directory('${tmp.path}/nope')),
      returnsNormally,
    );
  });

  group('isInstalled', () {
    test('is true once etc and bin are at the top', () {
      make('kali', ['kali-arm64/etc', 'kali-arm64/bin']);
      final root = Directory('${tmp.path}/distros/kali');
      installer.debugFlatten(root);
      expect(installer.debugLooksLikeRootfs(root), isTrue);
    });

    test('is false while they are still one level down', () {
      final root = make('kali', ['kali-arm64/etc', 'kali-arm64/bin']);
      expect(installer.debugLooksLikeRootfs(root), isFalse);
    });

    test('is false for a bare directory left by a failed extract', () {
      final root = make('empty', const []);
      expect(installer.debugLooksLikeRootfs(root), isFalse);
    });
  });
}
