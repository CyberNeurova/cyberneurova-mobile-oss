import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/core/agent/device/capture/pcapng.dart';

/// PCAPNG is a binary format where a single wrong offset or missed pad byte
/// shifts everything after it and the file reads as corrupt — in Wireshark,
/// not in our tests, which is the worst place to find out. So assert the
/// actual bytes.
void main() {
  ByteData bd(Uint8List b) => ByteData.sublistView(b);

  group('header', () {
    test('starts with a Section Header Block and the byte-order magic', () {
      final h = PcapngWriter().header();
      final d = bd(h);
      expect(d.getUint32(0, Endian.little), 0x0A0D0D0A, reason: 'SHB type');
      expect(d.getUint32(8, Endian.little), 0x1A2B3C4D,
          reason: 'byte-order magic must declare little-endian');
      expect(d.getUint16(12, Endian.little), 1, reason: 'major version');
    });

    test('SHB total length is consistent front and back', () {
      final h = PcapngWriter().header();
      final d = bd(h);
      final shbLen = d.getUint32(4, Endian.little);
      // A block repeats its length as the final 4 bytes; readers use it to
      // walk backwards. Mismatch = unreadable file.
      expect(d.getUint32(shbLen - 4, Endian.little), shbLen);
      expect(shbLen % 4, 0, reason: 'blocks are 4-byte aligned');
    });

    test('is followed by an Interface Description Block with our link type', () {
      final h = PcapngWriter(linkType: PcapngWriter.linkTypeRaw, snapLen: 65535)
          .header();
      final d = bd(h);
      final shbLen = d.getUint32(4, Endian.little);
      expect(d.getUint32(shbLen, Endian.little), 0x00000001, reason: 'IDB type');
      expect(d.getUint16(shbLen + 8, Endian.little), 101,
          reason: 'LINKTYPE_RAW — a TUN fd has no Ethernet header');
      expect(d.getUint32(shbLen + 12, Endian.little), 65535, reason: 'snaplen');
    });
  });

  group('packet', () {
    test('writes an Enhanced Packet Block with both lengths', () {
      final payload = Uint8List.fromList(List.generate(10, (i) => i));
      final p = PcapngWriter().packet(
        payload,
        timestamp: DateTime.utc(2026, 8, 2, 12, 0, 0),
      );
      final d = bd(p);
      expect(d.getUint32(0, Endian.little), 0x00000006, reason: 'EPB type');
      expect(d.getUint32(8, Endian.little), 0, reason: 'interface id 0');
      expect(d.getUint32(20, Endian.little), 10, reason: 'captured length');
      expect(d.getUint32(24, Endian.little), 10, reason: 'original length');
    });

    test('block length is 4-byte aligned and repeated at the tail', () {
      // 10 bytes of payload needs 2 pad bytes — the case that catches an
      // off-by-one in the padding maths.
      final p = PcapngWriter().packet(
        Uint8List(10),
        timestamp: DateTime.utc(2026),
      );
      final d = bd(p);
      final total = d.getUint32(4, Endian.little);
      expect(total, p.length);
      expect(total % 4, 0);
      expect(d.getUint32(total - 4, Endian.little), total);
    });

    test('round-trips the timestamp at microsecond resolution', () {
      final ts = DateTime.utc(2026, 8, 2, 12, 34, 56, 789, 123);
      final p = PcapngWriter().packet(Uint8List(4), timestamp: ts);
      final d = bd(p);
      final high = d.getUint32(12, Endian.little);
      final low = d.getUint32(16, Endian.little);
      final micros = (high << 32) | low;
      expect(micros, ts.microsecondsSinceEpoch);
    });

    test('truncates to snapLen but still reports the true wire length', () {
      final big = Uint8List(200);
      final p = PcapngWriter(snapLen: 64).packet(big, timestamp: DateTime.utc(2026));
      final d = bd(p);
      expect(d.getUint32(20, Endian.little), 64, reason: 'captured');
      expect(d.getUint32(24, Endian.little), 200,
          reason: 'original — losing this hides that a snaplen cut the packet');
    });

    test('preserves the payload bytes verbatim', () {
      final payload = Uint8List.fromList([0x45, 0x00, 0xDE, 0xAD, 0xBE, 0xEF]);
      final p = PcapngWriter().packet(payload, timestamp: DateTime.utc(2026));
      expect(p.sublist(28, 28 + payload.length), payload);
    });
  });
}
