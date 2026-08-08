import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/proot_runtime.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/root` is bind-mounted from outside the rootfs so the user's files
/// survive removing or switching a distro. If the translation forgets that,
/// file tools read an empty directory inside the distribution while the real
/// file sits in the persistent home — and it looks like data loss.
void main() {
  const distro = Distro(
    id: 'alpine',
    name: 'Alpine Linux',
    version: '3.21.7',
    description: '',
    url: '',
    sha256: 'x',
    downloadBytes: 1,
    installedBytes: 1,
    packageManager: 'apk',
  );

  const backend = ProotShellBackend(
    distro: distro,
    rootfsPath: '/data/app/shell/distros/alpine',
    homeDir: '/data/app/shell/home',
    runtime: ProotRuntime(
      prootPath: '/p/bin/proot',
      loaderPath: '/p/bin/proot-loader',
      tmpDir: '/p/tmp',
      libDir: '/p/lib',
    ),
  );

  test('home maps outside the rootfs, not into it', () {
    expect(backend.toHostPath('/root'), '/data/app/shell/home');
    expect(backend.toHostPath('/root/notes.md'),
        '/data/app/shell/home/notes.md');
    expect(backend.toHostPath('/root/src/main.dart'),
        '/data/app/shell/home/src/main.dart');
  });

  test('everything else still resolves inside the rootfs', () {
    expect(backend.toHostPath('/etc/hosts'),
        '/data/app/shell/distros/alpine/etc/hosts');
    expect(backend.toHostPath('/usr/bin/apk'),
        '/data/app/shell/distros/alpine/usr/bin/apk');
  });

  test('a path merely starting with the letters "root" is not home', () {
    // /rootkit must not be mistaken for a path under /root.
    expect(backend.toHostPath('/rootkit'),
        '/data/app/shell/distros/alpine/rootkit');
  });

  test('the bind is passed to proot for both arg builders', () {
    const bind = '--bind=/data/app/shell/home:/root';
    expect(backend.interactiveArgs(), contains(bind));
    expect(backend.commandArgs('ls'), contains(bind));
  });
}
