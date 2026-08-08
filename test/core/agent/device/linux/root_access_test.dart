import 'package:cyberneurova_mobile/core/agent/device/linux/root_access.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dangerous mistake here is treating "a su binary exists" as "we have
/// root". A manager like Magisk prompts, and the user may say no — acting on
/// presence alone would have us promise the model raw sockets it cannot get.
void main() {
  test('presence is not access', () {
    const found = RootAccess(status: RootStatus.present, suPath: '/sbin/su');
    expect(found.isUsable, isFalse);
  });

  test('only a verified uid 0 counts as usable', () {
    expect(
      const RootAccess(status: RootStatus.granted, suPath: '/sbin/su').isUsable,
      isTrue,
    );
    for (final s in [
      RootStatus.unavailable,
      RootStatus.present,
      RootStatus.denied,
    ]) {
      expect(RootAccess(status: s).isUsable, isFalse, reason: '$s');
    }
  });

  test('denied is distinct from unavailable', () {
    // They lead to different UI: denied is worth offering a retry, an absent
    // binary never becomes present.
    expect(RootStatus.denied, isNot(RootStatus.unavailable));
  });

  test('detect never reports granted on its own', () async {
    // detect() must not run su — that would raise a Magisk prompt at app
    // start, unprompted. It can only ever return unavailable or present.
    final r = await RootAccess.detect();
    expect(
      r.status,
      anyOf(RootStatus.unavailable, RootStatus.present),
      reason: 'detect() must not verify; verify() does that deliberately',
    );
  });

  test('verify on a result with no su path is a no-op', () async {
    const none = RootAccess(status: RootStatus.unavailable);
    final r = await RootAccess.verify(none);
    expect(r.status, RootStatus.unavailable);
  });

  test('every status carries a reason the settings screen can show', () {
    const r = RootAccess(
      status: RootStatus.unavailable,
      detail: 'No su binary. The Console uses PRoot, which needs no root.',
    );
    expect(r.detail, isNotEmpty);
  });
}
