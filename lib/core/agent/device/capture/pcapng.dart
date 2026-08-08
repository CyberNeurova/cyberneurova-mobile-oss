import 'dart:convert';
import 'dart:typed_data';

/// Minimal PCAPNG writer.
///
/// `docs/shell/01-ANDROID-RUNTIME.md` §6.1: *"Store captures as PCAPNG in the
/// session workspace so `tcpdump -r` / Wireshark work directly."* That
/// interoperability is the whole point — a bespoke format would mean writing
/// our own reader, and analysts already have tools.
///
/// This is the Dart equivalent of the `nsh-pcap::writer` crate in
/// `07-REPO-STRUCTURE.md`. Kept pure (bytes in, bytes out, no dart:io) so it
/// unit-tests without a device and can be fed from any source — the Android
/// `VpnService` TUN fd, a remote executor, or a fixture in a test.
///
/// Format: PCAPNG per the IETF draft — a Section Header Block, one Interface
/// Description Block, then an Enhanced Packet Block per packet. Little-endian,
/// which is what every mobile/desktop CPU we target uses and what the SHB
/// byte-order magic below declares.
class PcapngWriter {
  PcapngWriter({
    this.linkType = linkTypeRaw,
    this.snapLen = 262144,
    String? osName,
    String? appName,
  })  : _os = osName ?? 'Android',
        _app = appName ?? 'CyberNeurova Shell';

  /// `LINKTYPE_RAW` — the payload is a bare IP packet with no link-layer
  /// header. This is what a TUN interface hands you, so it is the correct
  /// link type for `VpnService` capture. (Ethernet would be 1, but there is
  /// no Ethernet header on a TUN fd, and mislabelling it makes Wireshark
  /// misparse every packet.)
  static const int linkTypeRaw = 101;

  /// `LINKTYPE_ETHERNET`, for sources that really do include a MAC header.
  static const int linkTypeEthernet = 1;

  final int linkType;
  final int snapLen;
  final String _os;
  final String _app;

  static const int _btSectionHeader = 0x0A0D0D0A;
  static const int _btInterfaceDesc = 0x00000001;
  static const int _btEnhancedPacket = 0x00000006;
  static const int _byteOrderMagic = 0x1A2B3C4D;

  /// The file header: Section Header Block + one Interface Description Block.
  /// Must be written once, before any packet.
  Uint8List header() {
    final b = BytesBuilder();
    b.add(_sectionHeaderBlock());
    b.add(_interfaceDescriptionBlock());
    return b.toBytes();
  }

  /// One captured packet.
  ///
  /// [timestamp] is written at microsecond resolution (the IDB below declares
  /// `if_tsresol = 6` to match). [originalLength] lets a truncated capture
  /// still report the true wire size — Wireshark shows both, and losing that
  /// distinction hides the fact that a snaplen cut the packet.
  Uint8List packet(
    Uint8List data, {
    required DateTime timestamp,
    int? originalLength,
  }) {
    final captured = data.length > snapLen ? snapLen : data.length;
    final payload = captured == data.length
        ? data
        : Uint8List.sublistView(data, 0, captured);
    final origLen = originalLength ?? data.length;

    // PCAPNG timestamps are a 64-bit count of `if_tsresol` units, split
    // across two 32-bit fields (high then low).
    final micros = timestamp.toUtc().microsecondsSinceEpoch;
    final tsHigh = (micros >> 32) & 0xFFFFFFFF;
    final tsLow = micros & 0xFFFFFFFF;

    // Body: interface id, ts high, ts low, captured len, original len, data.
    final pad = _padTo4(payload.length);
    final bodyLen = 20 + payload.length + pad;
    final totalLen = bodyLen + 12; // + type + two length fields

    final out = BytesBuilder();
    final head = ByteData(20);
    head.setUint32(0, _btEnhancedPacket, Endian.little);
    head.setUint32(4, totalLen, Endian.little);
    head.setUint32(8, 0, Endian.little); // interface id — we declare one IDB
    head.setUint32(12, tsHigh, Endian.little);
    head.setUint32(16, tsLow, Endian.little);
    out.add(head.buffer.asUint8List());

    final lens = ByteData(8);
    lens.setUint32(0, captured, Endian.little);
    lens.setUint32(4, origLen, Endian.little);
    out.add(lens.buffer.asUint8List());

    out.add(payload);
    if (pad > 0) out.add(Uint8List(pad));

    final tail = ByteData(4)..setUint32(0, totalLen, Endian.little);
    out.add(tail.buffer.asUint8List());
    return out.toBytes();
  }

  // ── blocks ────────────────────────────────────────────────────────────────

  Uint8List _sectionHeaderBlock() {
    final options = BytesBuilder()
      ..add(_option(3, utf8.encode(_os))) // shb_os
      ..add(_option(4, utf8.encode(_app))) // shb_userappl
      ..add(_optionEnd());
    final opts = options.toBytes();

    final bodyLen = 16 + opts.length; // magic + version + section length
    final totalLen = bodyLen + 12;

    final out = BytesBuilder();
    final head = ByteData(20);
    head.setUint32(0, _btSectionHeader, Endian.little);
    head.setUint32(4, totalLen, Endian.little);
    head.setUint32(8, _byteOrderMagic, Endian.little);
    head.setUint16(12, 1, Endian.little); // major
    head.setUint16(14, 0, Endian.little); // minor
    // section length: -1 (unknown) — we're streaming and can't know it.
    head.setUint32(16, 0xFFFFFFFF, Endian.little);
    out.add(head.buffer.asUint8List());
    final more = ByteData(4)..setUint32(0, 0xFFFFFFFF, Endian.little);
    out.add(more.buffer.asUint8List());
    out.add(opts);
    final tail = ByteData(4)..setUint32(0, totalLen, Endian.little);
    out.add(tail.buffer.asUint8List());
    return out.toBytes();
  }

  Uint8List _interfaceDescriptionBlock() {
    final options = BytesBuilder()
      ..add(_option(2, utf8.encode('cyberneurova-capture'))) // if_name
      ..add(_option(9, Uint8List.fromList([6]))) // if_tsresol = microseconds
      ..add(_optionEnd());
    final opts = options.toBytes();

    final bodyLen = 8 + opts.length; // linktype + reserved + snaplen
    final totalLen = bodyLen + 12;

    final out = BytesBuilder();
    final head = ByteData(16);
    head.setUint32(0, _btInterfaceDesc, Endian.little);
    head.setUint32(4, totalLen, Endian.little);
    head.setUint16(8, linkType, Endian.little);
    head.setUint16(10, 0, Endian.little); // reserved
    head.setUint32(12, snapLen, Endian.little);
    out.add(head.buffer.asUint8List());
    out.add(opts);
    final tail = ByteData(4)..setUint32(0, totalLen, Endian.little);
    out.add(tail.buffer.asUint8List());
    return out.toBytes();
  }

  Uint8List _option(int code, List<int> value) {
    final pad = _padTo4(value.length);
    final out = BytesBuilder();
    final head = ByteData(4);
    head.setUint16(0, code, Endian.little);
    head.setUint16(2, value.length, Endian.little);
    out.add(head.buffer.asUint8List());
    out.add(value);
    if (pad > 0) out.add(Uint8List(pad));
    return out.toBytes();
  }

  Uint8List _optionEnd() => Uint8List(4); // opt_endofopt: code 0, length 0

  /// Every PCAPNG field is padded to a 4-byte boundary. Getting this wrong
  /// shifts every subsequent block and the file reads as corrupt.
  static int _padTo4(int len) => (4 - (len % 4)) % 4;
}
