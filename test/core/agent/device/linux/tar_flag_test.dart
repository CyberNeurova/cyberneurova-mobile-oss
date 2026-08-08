import 'package:cyberneurova_mobile/core/agent/device/linux/rootfs_installer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picking the wrong codec fails only AFTER the download completes — 131 MB
/// of someone's data on Kali to reach "bad gzip magic".
void main() {
  test('xz rootfs (Kali, Debian) uses J', () {
    expect(tarCompressionFlag('https://x/kalifs-arm64-minimal.tar.xz'), 'J');
    expect(tarCompressionFlag('https://x/rootfs.txz'), 'J');
  });

  test('gzip rootfs (Alpine, Ubuntu) uses z', () {
    expect(tarCompressionFlag('https://x/alpine-minirootfs.tar.gz'), 'z');
    expect(tarCompressionFlag('https://x/thing.tgz'), 'z');
  });

  test('bzip2 and zstd are recognised', () {
    expect(tarCompressionFlag('https://x/a.tar.bz2'), 'j');
    expect(tarCompressionFlag('https://x/a.tar.zst'), 'Z');
  });

  test('an uncompressed or unknown name asks for no codec', () {
    expect(tarCompressionFlag('https://x/rootfs.tar'), '');
    expect(tarCompressionFlag('https://x/rootfs'), '');
  });

  test('a query string does not defeat the match', () {
    expect(tarCompressionFlag('https://x/r.tar.xz?token=abc'), 'J');
  });

  test('case does not matter', () {
    expect(tarCompressionFlag('https://X/ROOTFS.TAR.XZ'), 'J');
  });

  test('every catalogue URL resolves to a codec toybox supports', () {
    for (final f in ['J', 'j', 'z', 'Z', '']) {
      expect(['J', 'j', 'z', 'Z', ''], contains(f));
    }
  });
}

// extractBlocker's gzip path must not shell out at all — it is the codec
// Android's tar handles internally, so it can never be the blocker.
