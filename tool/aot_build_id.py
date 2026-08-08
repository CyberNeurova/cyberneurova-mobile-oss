#!/usr/bin/env python3
"""Print the GNU build-id of an AOT snapshot, from a .so or from inside an APK.

Gradle strips the native libraries it packages, so the `app.so` the Flutter
tool just compiled and the `libapp.so` sitting in the APK never hash the same
even when they are the same build. The build-id note survives stripping, so it
is the one field that answers the only question that matters: is the APK
carrying the snapshot this build produced?

Usage:
    aot_build_id.py path/to/app.so
    aot_build_id.py path/to/app.apk lib/arm64-v8a/libapp.so
"""
import struct
import sys
import zipfile


def build_id(data: bytes) -> str:
    if data[:4] != b'\x7fELF':
        raise ValueError('not an ELF file')
    is64 = data[4] == 2
    if not is64:
        raise ValueError('only 64-bit ELF is checked; pass the arm64 library')
    e_phoff, = struct.unpack_from('<Q', data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from('<HH', data, 0x36)
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from('<I', data, off)
        if p_type != 4:  # PT_NOTE
            continue
        p_offset, = struct.unpack_from('<Q', data, off + 0x08)
        p_filesz, = struct.unpack_from('<Q', data, off + 0x20)
        pos, end = p_offset, p_offset + p_filesz
        while pos + 12 <= end:
            n_namesz, n_descsz, n_type = struct.unpack_from('<III', data, pos)
            name_at = pos + 12
            desc_at = name_at + ((n_namesz + 3) & ~3)
            nxt = desc_at + ((n_descsz + 3) & ~3)
            name = data[name_at:name_at + n_namesz].rstrip(b'\0')
            if name == b'GNU' and n_type == 3:  # NT_GNU_BUILD_ID
                return data[desc_at:desc_at + n_descsz].hex()
            pos = nxt
    raise ValueError('no GNU build-id note')


def main(argv):
    if len(argv) == 2:
        with open(argv[1], 'rb') as f:
            print(build_id(f.read()))
    elif len(argv) == 3:
        with zipfile.ZipFile(argv[1]) as z:
            print(build_id(z.read(argv[2])))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
