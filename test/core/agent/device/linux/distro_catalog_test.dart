import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalogue is the one place a bad entry costs the user real bandwidth.
/// The Debian entry shipped for weeks pointing at a URL that 404s — a hash
/// alone would never have caught it, because the hash was a placeholder and
/// the URL was independently dead.
void main() {
  final offered = kDistroCatalog.where((d) => d.isVerified).toList();

  test('something is actually offered', () {
    expect(offered, isNotEmpty);
  });

  group('every offered distro', () {
    test('has a real 64-hex sha256', () {
      for (final d in offered) {
        expect(d.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: d.id);
      }
    });

    test('has an https URL', () {
      for (final d in offered) {
        expect(d.url, startsWith('https://'), reason: d.id);
      }
    });

    test('has a measured, plausible download size', () {
      for (final d in offered) {
        // A placeholder round number like 400 * 1024 * 1024 is the tell that
        // nobody measured it.
        expect(d.downloadBytes, greaterThan(1024 * 1024), reason: d.id);
        expect(d.installedBytes, greaterThanOrEqualTo(d.downloadBytes),
            reason: d.id);
      }
    });

    test('names an aarch64/arm64 build', () {
      // Shipping an amd64 rootfs to a phone fails only after the download.
      for (final d in offered) {
        expect(d.url.toLowerCase(), anyOf(contains('arm64'), contains('aarch64')),
            reason: d.id);
      }
    });

    test('is not pinned to a rolling path', () {
      // `current/` and `latest/` rotate, which breaks the pinned hash on the
      // upstream's next release.
      for (final d in offered) {
        expect(d.url, isNot(contains('/current/')), reason: d.id);
        expect(d.url, isNot(contains('/latest/')), reason: d.id);
      }
    });
  });

  test('a gated distro is never presented as installable', () {
    for (final d in kDistroCatalog.where((d) => !d.isVerified)) {
      expect(d.sha256, startsWith('FILL_'), reason: d.id);
    }
  });

  test('ids are unique', () {
    final ids = kDistroCatalog.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
