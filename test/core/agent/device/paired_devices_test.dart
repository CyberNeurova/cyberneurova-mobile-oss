import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/core/agent/device/linux/paired_devices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing paired reads as an empty list, not an error', () async {
    expect(await PairedDevices.all(), isEmpty);
  });

  test('reconnecting updates the entry instead of duplicating it', () async {
    // A device used daily must appear once. Without this the list becomes a
    // connection log and stops being reviewable, which is its whole purpose.
    final june = DateTime(2026, 6, 1);
    final august = DateTime(2026, 8, 4);

    await PairedDevices.remember(
        id: 'phone-1', name: 'SM-A546E', uid: '2000', at: june);
    await PairedDevices.remember(
        id: 'phone-1', name: 'SM-A546E', uid: '2000', at: august);

    final all = await PairedDevices.all();
    expect(all.length, 1);
    // The date that matters when reviewing a grant is when it was MADE.
    expect(all.single.firstPairedAt, june);
    expect(all.single.lastConnectedAt, august);
  });

  test('a connection that cannot report the uid does not erase it', () async {
    await PairedDevices.remember(id: 'p', name: 'Phone', uid: '0');
    await PairedDevices.remember(id: 'p', name: 'Phone');

    // Losing "this one had root" because a later probe came back blank would
    // understate what the user has granted.
    expect((await PairedDevices.all()).single.uid, '0');
  });

  test('a rename is picked up', () async {
    await PairedDevices.remember(id: 'p', name: 'Old name');
    await PairedDevices.remember(id: 'p', name: 'New name');
    expect((await PairedDevices.all()).single.name, 'New name');
  });

  test('most recently used first', () async {
    await PairedDevices.remember(
        id: 'a', name: 'A', at: DateTime(2026, 1, 1));
    await PairedDevices.remember(
        id: 'b', name: 'B', at: DateTime(2026, 7, 1));
    await PairedDevices.remember(
        id: 'c', name: 'C', at: DateTime(2026, 3, 1));

    expect([for (final d in await PairedDevices.all()) d.id], ['b', 'c', 'a']);
  });

  test('forgetting one leaves the others', () async {
    await PairedDevices.remember(id: 'a', name: 'A');
    await PairedDevices.remember(id: 'b', name: 'B');

    await PairedDevices.forget('a');

    expect([for (final d in await PairedDevices.all()) d.id], ['b']);
  });

  test('a corrupt entry costs only itself', () async {
    // One drifted record must not take the whole list down — the same rule the
    // model list already follows.
    SharedPreferences.setMockInitialValues({
      'adb_paired_devices_v1': '['
          '{"id":"good","name":"Good","firstPairedAt":"2026-01-01T00:00:00.000",'
          '"lastConnectedAt":"2026-01-01T00:00:00.000"},'
          '{"id":"","name":"blank id"},'
          '{"nope":true},'
          '"a string"'
          ']',
    });

    expect([for (final d in await PairedDevices.all()) d.id], ['good']);
  });

  test('unreadable storage is empty rather than a crash', () async {
    SharedPreferences.setMockInitialValues({
      'adb_paired_devices_v1': 'not json at all',
    });
    expect(await PairedDevices.all(), isEmpty);
  });

  test('an entry with no name falls back to something showable', () async {
    SharedPreferences.setMockInitialValues({
      'adb_paired_devices_v1': '['
          '{"id":"abc","name":"","firstPairedAt":"2026-01-01T00:00:00.000",'
          '"lastConnectedAt":"2026-01-01T00:00:00.000"}]',
    });
    // A blank row is indistinguishable from a rendering bug.
    expect((await PairedDevices.all()).single.name, 'abc');
  });
}
