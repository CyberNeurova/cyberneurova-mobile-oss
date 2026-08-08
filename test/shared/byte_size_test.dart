import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/shared/format/byte_size.dart';

void main() {
  test('bytes stay bytes, with no decimal point', () {
    expect(humanBytes(0), '0 B');
    expect(humanBytes(1), '1 B');
    expect(humanBytes(1023), '1023 B');
  });

  test('the unit changes exactly at the boundary', () {
    expect(humanBytes(1024), '1.0 KB');
    expect(humanBytes(1024 * 1024 - 1), '1024.0 KB');
    expect(humanBytes(1024 * 1024), '1.0 MB');
  });

  test('a multi-gigabyte file reads in gigabytes', () {
    // The reason this function was rewritten. Both previous copies stopped at
    // MB, so the rootfs the file browser itself downloads showed as a
    // four-digit MB number.
    expect(humanBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    expect(humanBytes((1.5 * 1024 * 1024 * 1024).round()), '1.5 GB');
  });

  test('it keeps climbing rather than running out of units', () {
    expect(humanBytes(3 * 1024 * 1024 * 1024 * 1024), '3.0 TB');
  });

  test('a nonsense size does not render as nonsense', () {
    // stat can return -1 on a race with a delete.
    expect(humanBytes(-1), '0 B');
  });

  test('the B/KB/MB output is unchanged from what it replaced', () {
    // Both call sites shipped these exact strings; this is a refactor, and a
    // refactor that changes what the user sees is not one.
    expect(humanBytes(512), '512 B');
    expect(humanBytes(2048), '2.0 KB');
    expect(humanBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
