import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Can this app execute code it did not ship?
///
/// ## Why this is the question that decides the product
///
/// `SPIKE-RESULTS.md` established that we **cannot `execve` a binary we
/// wrote** — SELinux denies `execute` on `app_data_file` for `untrusted_app`
/// from API 29. Taken alone that reads as "downloaded tools are impossible on
/// Google Play", which would rule out letting users install a distro after
/// installing the app.
///
/// But `execve` is not the only way to run code, and the SELinux permissions
/// involved are **different**:
///
/// | Route | Permission needed | Who has it |
/// |---|---|---|
/// | `execve` a file we wrote | `file execute` on `app_data_file` | removed at API 29 |
/// | `mmap(PROT_EXEC)` a file we wrote | `file execute` on `app_data_file` | removed at API 29 |
/// | **read into anonymous memory, `mprotect(PROT_EXEC)`** | **`process execmem`** | **every app — ART's JIT needs it** |
///
/// That third row is how a userspace ELF loader works: it never asks the
/// kernel to execute a *file*, it copies the code into ordinary memory and
/// marks that memory executable. It is also the most plausible explanation
/// for how PRoot-based apps run downloaded rootfs binaries while targeting a
/// modern SDK — UserLAnd is `targetSdk 30`, so it is demonstrably not using
/// Termux's stay-on-`targetSdk 28` trick.
///
/// This class **measures** all three rather than assuming any of them, because
/// the answer decides whether "download the OS you want" is buildable on Play
/// or not. See `docs/shell/13-RUNTIME-INSTALL.md`.
///
/// Nothing here is exotic or a private API: `mmap`/`mprotect` are libc, and
/// the payload is eight bytes that return a constant.
class ExecMemory {
  const ExecMemory._();

  // ── libc ────────────────────────────────────────────────────────────────
  static final DynamicLibrary _libc = DynamicLibrary.process();

  static final _mmap = _libc.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, IntPtr),
      Pointer<Void> Function(Pointer<Void>, int, int, int, int, int)>('mmap');

  static final _mprotect = _libc.lookupFunction<
      Int32 Function(Pointer<Void>, IntPtr, Int32),
      int Function(Pointer<Void>, int, int)>('mprotect');

  static final _munmap = _libc.lookupFunction<
      Int32 Function(Pointer<Void>, IntPtr),
      int Function(Pointer<Void>, int)>('munmap');

  static const int _protRead = 0x1;
  static const int _protWrite = 0x2;
  static const int _protExec = 0x4;
  static const int _mapPrivate = 0x02;
  static const int _mapAnonymous = 0x20;
  static const int _pageSize = 4096;

  /// A function that returns 42, as machine code.
  ///
  /// Deliberately the smallest thing that proves execution actually happened:
  /// if the call returns 42, the CPU ran bytes we placed in memory at runtime.
  /// A crash or a wrong value means it did not.
  static Uint8List? _payload() {
    switch (Abi.current()) {
      case Abi.androidArm64:
      case Abi.linuxArm64:
      case Abi.macosArm64:
        // mov w0, #42  ;  ret
        return Uint8List.fromList([0x40, 0x05, 0x80, 0x52, 0xc0, 0x03, 0x5f, 0xd6]);
      case Abi.androidX64:
      case Abi.linuxX64:
      case Abi.macosX64:
        // mov eax, 42  ;  ret
        return Uint8List.fromList([0xb8, 0x2a, 0x00, 0x00, 0x00, 0xc3]);
      case Abi.androidArm:
      case Abi.linuxArm:
        // mov r0, #42  ;  bx lr
        return Uint8List.fromList([0x2a, 0x00, 0xa0, 0xe3, 0x1e, 0xff, 0x2f, 0xe1]);
      default:
        return null;
    }
  }

  /// Maps a payload into anonymous memory, marks it executable, and calls it.
  ///
  /// Returns null on success, or a human-readable reason it failed. Success
  /// means an in-process ELF loader is viable on this device — which is what
  /// makes "install the distro after installing the app" possible.
  static String? probeAnonymousExec() {
    final code = _payload();
    if (code == null) return 'unsupported ABI ${Abi.current()}';

    final mem = _mmap(nullptr, _pageSize, _protRead | _protWrite,
        _mapPrivate | _mapAnonymous, -1, 0);
    if (mem.address == 0 || mem.address == -1) {
      return 'mmap failed (errno via address ${mem.address})';
    }

    try {
      final bytes = mem.cast<Uint8>().asTypedList(_pageSize);
      bytes.setAll(0, code);

      // W^X: drop write as we add execute. Keeping both would be refused on
      // hardened kernels and is bad practice regardless.
      if (_mprotect(mem, _pageSize, _protRead | _protExec) != 0) {
        return 'mprotect(PROT_EXEC) refused — no `process execmem`';
      }

      final fn = mem
          .cast<NativeFunction<Int32 Function()>>()
          .asFunction<int Function()>();
      final result = fn();
      if (result != 42) return 'executed but returned $result, expected 42';
      return null;
    } finally {
      _munmap(mem, _pageSize);
    }
  }

  /// The case that decides how we ship tools: run a **bundled** binary through
  /// the `$PREFIX/bin` symlink, from the real app process.
  ///
  /// This exercises the entire chain in one call — symlink → `nativeLibraryDir`
  /// → `execve` → `argv[0]` multicall dispatch — which is exactly what a
  /// busybox or nmap would go through. Run it on a **Play** `targetSdk`, since
  /// the whole question is whether tools can ship on the store build.
  ///
  /// Returns null on success, else why it failed.
  static Future<String?> probeBundledExec(String binDir, String applet) async {
    final path = '$binDir/$applet';
    if (!Link(path).existsSync() && !File(path).existsSync()) {
      return 'not linked: $path';
    }
    try {
      final r = await Process.run(path, const []);
      if (r.exitCode != 0) return 'exit ${r.exitCode}: ${r.stderr}'.trim();
      final out = '${r.stdout}'.trim();
      return out.isEmpty ? 'ran but printed nothing' : 'OK -> $out';
    } on ProcessException catch (e) {
      return 'BLOCKED: ${e.message}';
    } catch (e) {
      return 'BLOCKED: $e';
    }
  }

  /// The control case: `execve` a file we wrote into our own data directory.
  ///
  /// Expected to FAIL on API 29+. It is measured rather than assumed so the
  /// two results are directly comparable — one pass and one fail is what
  /// tells us the loader route is the difference, not the device.
  static Future<String?> probeFileExec(String dir) async {
    final f = File('$dir/execprobe');
    try {
      // A shell script, not a binary — the denial is on the *file*, so the
      // contents don't matter and this keeps the probe portable.
      await f.writeAsString('#!/system/bin/sh\necho FILE_EXEC_OK\n');
      await Process.run('/system/bin/chmod', ['755', f.path]);
      final r = await Process.run(f.path, const []);
      if (r.exitCode == 0) return null;
      return 'exit ${r.exitCode}: ${r.stderr}'.trim();
    } on ProcessException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    } finally {
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}
