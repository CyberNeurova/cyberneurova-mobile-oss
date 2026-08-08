import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/linux/distro.dart';

/// Where an install has got to.
enum InstallStage {
  downloading,
  verifying,
  extracting,
  configuring,
  seeding,
  done,
  failed
}

class InstallProgress {
  const InstallProgress({
    required this.stage,
    this.received = 0,
    this.total = 0,
    this.message,
  });

  final InstallStage stage;
  final int received;
  final int total;
  final String? message;

  /// 0..1 for the download, or null when the stage has no measurable progress.
  double? get fraction => (stage == InstallStage.downloading && total > 0)
      ? received / total
      : null;

  bool get isTerminal =>
      stage == InstallStage.done || stage == InstallStage.failed;
}

/// Downloads, verifies and unpacks a Linux root filesystem.
///
/// The order is deliberate and non-negotiable: **verify before extract.** This
/// is several hundred megabytes of code whose entire purpose is to be executed
/// — unpacking it before checking the hash would hand arbitrary code execution
/// to anyone who could interfere with the download. A hash mismatch deletes the
/// file and fails; it never warns and continues.
class RootfsInstaller {
  RootfsInstaller({
    required this.distrosDir,
    required this.downloadsDir,
    this.busyboxPath,
    this.libraryPath,
    this.seedRuntime,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  /// Parent of the per-distro rootfs directories.
  final String distrosDir;

  /// Scratch for in-flight tarballs. Kept out of [distrosDir] so a partial
  /// download can never be mistaken for an installed distro.
  final String downloadsDir;

  /// Bundled BusyBox, or null if it did not ship.
  ///
  /// The only thing on the device that can decompress xz. Android's tar
  /// shells out to an `xz` binary that does not exist, so without this a
  /// .tar.xz rootfs cannot be unpacked at all.
  final String? busyboxPath;

  /// `$PREFIX/lib`, for BusyBox's SONAME. Null disables the BusyBox path.
  final String? libraryPath;

  /// Runs the post-install package install inside the freshly extracted
  /// rootfs. Injected rather than built here so this class keeps needing
  /// nothing but a filesystem and an HTTP client, and tests do not need PRoot.
  final Future<void> Function(Distro distro, String rootfsPath)? seedRuntime;

  final HttpClient _http;

  String rootfsPathFor(Distro d) => p.join(distrosDir, d.id);

  /// A distro counts as installed only if it has the directories PRoot and the
  /// package manager will actually need. A bare directory left by a failed
  /// extract must not read as success.
  bool isInstalled(Distro d) {
    final root = Directory(rootfsPathFor(d));
    if (!root.existsSync()) return false;
    return Directory(p.join(root.path, 'etc')).existsSync() &&
        Directory(p.join(root.path, 'bin')).existsSync();
  }

  Future<void> remove(Distro d) async {
    final root = Directory(rootfsPathFor(d));
    if (root.existsSync()) await root.delete(recursive: true);
  }


  /// Why this distro cannot be unpacked on this device, or null if it can.
  ///
  /// Checked before downloading. The only codec stock Android can actually
  /// decompress is gzip: toybox tar handles `z` internally but shells out for
  /// `J`/`j`/`Z`, and none of those binaries exist. Bundled BusyBox covers xz
  /// and bzip2, so this normally passes — it still runs because BusyBox may
  /// not have shipped, and finding that out after a 131 MB download is the
  /// failure this exists to prevent.
  Future<String?> extractBlocker(Distro distro) async {
    final flag = tarCompressionFlag(distro.url);
    if (flag == 'z' || flag.isEmpty) return null;

    // BusyBox decompresses xz and bzip2 in-process. zstd is not an applet.
    if ((flag == 'J' || flag == 'j') && await _busyboxRuns()) return null;

    final codec = switch (flag) {
      'J' => 'xz',
      'j' => 'bzip2',
      'Z' => 'zstd',
      _ => flag,
    };
    if (await _hasCommand(codec)) return null;

    return 'Cannot unpack ${distro.name}: this device has no $codec '
        'decompressor, and the Android tar needs one to read this archive. '
        'Nothing was downloaded.';
  }

  /// Whether bundled BusyBox actually **executes**, not merely exists.
  ///
  /// Existing is not enough, and assuming it was cost a 131 MB download. Two
  /// separate ways a present binary still cannot run here:
  ///
  ///  - Alpine's static musl build is killed by Android's seccomp filter the
  ///    moment the app spawns it (exit -31, SIGSYS). It runs fine under `adb
  ///    shell`, which is a different domain — so shell testing proves nothing
  ///    about the app.
  ///  - Termux's build is a launcher plus `libbusybox.so.1.38.0`, and that
  ///    core pulls in Termux's own `libandroid-selinux.so`. Without it the
  ///    dynamic linker refuses the exec.
  ///
  /// Our own NDK build has neither problem, but the probe stays: a binary
  /// that ships is still not a binary that runs, and the whole point is to
  /// find that out before spending someone's data.
  ///
  /// Running it is the only honest check. Cached because install() asks once
  /// per attempt and the answer cannot change within a process.
  bool? _busyboxRunsCache;
  Future<bool> _busyboxRuns() async {
    if (_busyboxRunsCache != null) return _busyboxRunsCache!;
    final path = busyboxPath;
    if (path == null || !File(path).existsSync()) {
      return _busyboxRunsCache = false;
    }
    try {
      // `--list` and not an applet name: our build is minimal, so probing with
      // something like `true` asks for an applet that was never compiled in
      // and reports a working BusyBox as broken. `--list` is part of the
      // busybox applet itself, so it answers whenever the binary runs at all.
      final r = await Process.run(
        path,
        ['--list'],
        environment:
            libraryPath != null ? {'LD_LIBRARY_PATH': libraryPath!} : null,
      );
      // A negative code is death by signal; a linker failure is non-zero with
      // "CANNOT LINK EXECUTABLE" on stderr. Only a clean 0 counts.
      return _busyboxRunsCache = r.exitCode == 0;
    } on ProcessException {
      return _busyboxRunsCache = false;
    }
  }

  /// Whether a command resolves on the host PATH.
  Future<bool> _hasCommand(String name) async {
    try {
      final r = await Process.run('/system/bin/which', [name]);
      return r.exitCode == 0 && '${r.stdout}'.trim().isNotEmpty;
    } on ProcessException {
      return false;
    }
  }

  @visibleForTesting
  void debugFlatten(Directory root) => _flattenIfWrapped(root);

  @visibleForTesting
  bool debugLooksLikeRootfs(Directory root) => _looksLikeRootfs(root);

  /// Whether [root] holds something PRoot could actually boot.
  ///
  /// Same shape as [isInstalled], deliberately: an install is finished when
  /// the directory would pass the check a later launch makes.
  bool _looksLikeRootfs(Directory root) =>
      Directory(p.join(root.path, 'etc')).existsSync() &&
      Directory(p.join(root.path, 'bin')).existsSync();

  /// Lifts a rootfs out of a single wrapping directory, in place.
  ///
  /// Kali's tarball contains `kali-arm64/etc`, `kali-arm64/bin`, … while
  /// Alpine's contains `etc`, `bin`, … directly. Rather than special-casing
  /// per distro — which would silently break the next tarball that changes
  /// shape — detect the wrapper: no `etc` at the top, and exactly one entry,
  /// which is a directory.
  ///
  /// Renames rather than copies. Same filesystem, so each is a metadata
  /// operation; copying 846 MB on a phone would be minutes of I/O for nothing.
  void _flattenIfWrapped(Directory root) {
    if (!root.existsSync()) return;
    if (Directory(p.join(root.path, 'etc')).existsSync()) return;

    final entries = root.listSync();
    if (entries.length != 1) return;
    final inner = entries.first;
    if (inner is! Directory) return;

    for (final child in inner.listSync()) {
      try {
        child.renameSync(p.join(root.path, p.basename(child.path)));
      } on FileSystemException {
        // One stubborn entry must not strand the whole rootfs a level down;
        // _looksLikeRootfs is what decides success.
      }
    }
    try {
      inner.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover empty wrapper is harmless.
    }
  }

  /// Runs the whole install, emitting progress.
  ///
  /// Resumable downloads are deliberately **not** implemented yet: a resumed
  /// download that silently mixes bytes from two different upstream releases
  /// would fail the hash check in a way that looks like corruption, and on a
  /// 400 MB Kali image people would retry forever. Alpine is 3.7 MB, so the
  /// cost of restarting is trivial; add resume with a strong ETag check when
  /// the larger distros land.
  Stream<InstallProgress> install(Distro distro) async* {
    final tmp = File(p.join(downloadsDir, '${distro.id}.download'));
    final root = Directory(rootfsPathFor(distro));

    try {
      Directory(downloadsDir).createSync(recursive: true);

      // ── can we even unpack this? ───────────────────────────────────────
      // Ask BEFORE spending the user's data. Android's tar advertises `J`
      // for xz but implements it by exec'ing an `xz` binary that stock
      // Android does not ship, so a .tar.xz rootfs fails at extract — after
      // the full download. On Kali that was 131 MB spent to reach
      // "tar: exec xz: No such file or directory".
      final blocker = await extractBlocker(distro);
      if (blocker != null) {
        yield InstallProgress(stage: InstallStage.failed, message: blocker);
        return;
      }

      // ── download ──────────────────────────────────────────────────────
      yield InstallProgress(
        stage: InstallStage.downloading,
        total: distro.downloadBytes,
        message: 'Downloading ${distro.name} ${distro.version}',
      );

      if (tmp.existsSync()) tmp.deleteSync();
      final req = await _http.getUrl(Uri.parse(distro.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        yield InstallProgress(
          stage: InstallStage.failed,
          message: 'Download failed: HTTP ${res.statusCode}',
        );
        return;
      }

      final total =
          res.contentLength > 0 ? res.contentLength : distro.downloadBytes;
      final sink = tmp.openWrite();
      var received = 0;
      var lastEmit = 0;
      final digest = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(digest);

      try {
        await for (final chunk in res) {
          sink.add(chunk);
          // Hash as we go rather than re-reading the file afterwards: on a
          // phone that is a second pass over hundreds of MB of slow storage.
          hasher.add(chunk);
          received += chunk.length;
          // Emitting per chunk would rebuild the UI thousands of times a
          // second for no visible gain.
          if (received - lastEmit > 256 * 1024) {
            lastEmit = received;
            yield InstallProgress(
              stage: InstallStage.downloading,
              received: received,
              total: total,
            );
          }
        }
      } finally {
        await sink.close();
      }
      hasher.close();

      // A server that closes early ends the stream cleanly, so a truncated
      // download looks like a finished one. Without this it surfaces as a
      // checksum mismatch, which reads like tampering rather than a dropped
      // connection and sends people looking in the wrong place.
      if (total > 0 && received < total) {
        yield InstallProgress(
          stage: InstallStage.failed,
          message: 'Download stopped early: got '
              '${(received / (1024 * 1024)).toStringAsFixed(1)} MB of '
              '${(total / (1024 * 1024)).toStringAsFixed(1)} MB. '
              'Check the connection and try again.',
        );
        return;
      }

      // ── verify ────────────────────────────────────────────────────────
      yield const InstallProgress(
        stage: InstallStage.verifying,
        message: 'Verifying checksum',
      );
      final actual = digest.events.single.toString();
      if (actual != distro.sha256) {
        // Delete it. A tarball that failed verification must not survive on
        // disk where a later code path could pick it up.
        if (tmp.existsSync()) tmp.deleteSync();
        yield InstallProgress(
          stage: InstallStage.failed,
          message: 'Checksum mismatch — refusing to install.\n'
              'expected ${distro.sha256}\nactual   $actual',
        );
        return;
      }

      // ── extract ───────────────────────────────────────────────────────
      yield const InstallProgress(
        stage: InstallStage.extracting,
        message: 'Extracting root filesystem',
      );

      // Fresh directory: extracting over a half-finished previous attempt
      // produces a rootfs that is neither one release nor the other.
      if (root.existsSync()) await root.delete(recursive: true);
      root.createSync(recursive: true);

      // Android's own tar (toybox), not a Dart implementation. A rootfs is
      // mostly symlinks — `/bin/sh -> busybox` and hundreds like it — plus
      // hardlinks and modes, and getting those subtly wrong yields a distro
      // that half-works in ways that are miserable to debug. `tar` already
      // does it correctly.
      // Android's tar for gzip (it decompresses that one internally), BusyBox
      // for everything else. BusyBox is invoked as `busybox tar …` rather
      // than through a `tar` symlink so it never shadows the system tar for
      // anything else on $PATH.
      final flag = tarCompressionFlag(distro.url);
      final useBusybox =
          flag != 'z' && flag.isNotEmpty && await _busyboxRuns();
      final tar = await Process.run(
        useBusybox ? busyboxPath! : '/system/bin/tar',
        [
          if (useBusybox) 'tar',
          '-x${flag}f',
          tmp.path,
          '-C',
          root.path,
        ],
        // BusyBox ships as a small launcher plus `libbusybox.so.1.38.0`, so
        // it will not start without the prefix lib dir on the search path —
        // the same arrangement PRoot needs.
        environment: useBusybox && libraryPath != null
            ? {'LD_LIBRARY_PATH': libraryPath!}
            : null,
      );
      // Some tarballs wrap the whole tree in one directory (Kali ships
      // `kali-arm64/`), others do not (Alpine). Normalise before judging the
      // result, so the rootfs root is always the distro directory itself —
      // otherwise PRoot gets a rootfs with no /etc and isInstalled() calls a
      // good install a failure.
      _flattenIfWrapped(root);

      // Judge the extract by what landed, NOT by tar's exit code.
      //
      // Unpacking as a normal user cannot create device nodes, and both tars
      // say so loudly — 8 such errors on Kali. Neither matters: PRoot bind-
      // mounts Android's real /dev. The previous version matched on message
      // text, which broke the moment BusyBox did the extracting instead of
      // toybox: "can't create hardlink … to …" (one klibc initramfs helper)
      // matched none of the expected phrases, so a complete 846 MB rootfs was
      // thrown away as a failure. Checking the filesystem is both simpler and
      // implementation-independent.
      if (!_looksLikeRootfs(root)) {
        final err = '${tar.stderr}'.trim();
        // Always name the exit code and which tar ran. "No root filesystem
        // was produced" with no other detail is unactionable — it hides
        // whether tar even started.
        final who = useBusybox ? 'busybox tar' : 'tar';
        yield InstallProgress(
          stage: InstallStage.failed,
          message: err.isEmpty
              ? 'Extract failed: $who exited ${tar.exitCode} and produced no '
                  'root filesystem.'
              : 'Extract failed ($who, exit ${tar.exitCode}): $err',
        );
        return;
      }

      // ── configure ─────────────────────────────────────────────────────
      yield const InstallProgress(
        stage: InstallStage.configuring,
        message: 'Configuring network and repositories',
      );
      await _configure(distro, root.path);

      // ── seed a language runtime ───────────────────────────────────────
      //
      // The image ships with no interpreter of any kind, and the Code
      // surface's own first starter is "Set up a Python project with a test
      // that passes". Asked to create and run a hello.py, the agent wrote the
      // file correctly and then spent fifteen tool calls — twenty-seven on the
      // retry — hunting for an interpreter that was never there, with `apk`
      // sitting in /sbin. Telling it to install one did not help.
      //
      // So install it here instead. Measured on the device: `apk add
      // --no-cache python3` pulls 17 packages and finishes in well under a
      // minute, taking the whole rootfs to 49 MiB. That is a better trade than
      // a 12B model rediscovering the problem on every fresh session, and it
      // happens once, during a setup the user is already waiting on.
      //
      // Deliberately not fatal: a distro without python is still a working
      // distro, and failing the whole install over a convenience package would
      // be the wrong call on a flaky connection.
      if (seedRuntime != null) {
        yield const InstallProgress(
          stage: InstallStage.seeding,
          message: 'Installing Python',
        );
        String? seedError;
        try {
          await seedRuntime!(distro, root.path);
        } catch (e) {
          seedError = '$e';
        }
        if (seedError != null) {
          // Non-fatal, but NOT silent. The first version swallowed this, and
          // the result was an install that looked perfect and shipped no
          // interpreter — indistinguishable from the seeding step never having
          // run. Say it happened and carry on.
          yield InstallProgress(
            stage: InstallStage.seeding,
            message: 'Python could not be installed automatically '
                '(${distro.packageManager} add python3 still works): '
                '$seedError',
          );
        }
      }

      yield InstallProgress(
        stage: InstallStage.done,
        message: '${distro.name} ready. Try `${distro.packageManager} --help`.',
      );
    } catch (e) {
      yield InstallProgress(stage: InstallStage.failed, message: '$e');
    } finally {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// The handful of files without which a fresh rootfs looks broken.
  ///
  /// Every one of these is something people hit and misdiagnose:
  ///
  /// * **`/etc/resolv.conf`** — Android does not expose one, so a fresh guest
  ///   has no DNS at all. Every `apk add` / `apt update` fails with a
  ///   name-resolution error that reads like no internet. This single file is
  ///   the most common reason a hand-rolled PRoot setup "doesn't work".
  /// * **`/etc/hosts`** — some tooling assumes localhost resolves.
  /// * **repositories** — Alpine's minirootfs ships with the main repository
  ///   commented out, so `apk add` finds nothing until it is enabled.
  Future<void> _configure(Distro distro, String root) async {
    Future<void> write(String rel, String content) async {
      final f = File(p.join(root, rel));
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
    }

    await write('etc/resolv.conf',
        'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n');
    await write('etc/hosts', '127.0.0.1 localhost\n::1 localhost\n');

    if (distro.id == 'alpine') {
      final v = distro.version.split('.').take(2).join('.');
      await write(
        'etc/apk/repositories',
        'https://dl-cdn.alpinelinux.org/alpine/v$v/main\n'
            'https://dl-cdn.alpinelinux.org/alpine/v$v/community\n',
      );
    }

    // `apt` is what people type, whatever distro they are actually in.
    //
    // Alpine has `apk`, so `apt` is a bare "not found" — which reads as
    // "broken" and invites retrying, the same loop the Android shell's guards
    // exist to prevent. Point at the real command instead of leaving a 127.
    // Sourced by `/bin/sh -l` via /etc/profile.
    if (distro.packageManager != 'apt') {
      final pm = distro.packageManager;
      await write('etc/profile.d/cn-hints.sh', '''
apt() {
  echo "apt: not available — this is ${distro.name}, which uses '$pm'." >&2
  echo "Try:  $pm add <package>        (search: $pm search <term>)" >&2
  return 127
}
apt-get() { apt "\$@"; }
''');
    }
  }

  void dispose() => _http.close(force: true);
}

/// The toybox tar flag for a rootfs URL's compression.
///
/// This was hardcoded to `z`, which is right for Alpine (.tar.gz) and wrong
/// for everything else in the catalogue — Kali and Debian ship .tar.xz. The
/// failure would land AFTER the download, so on Kali that is 131 MB spent to
/// reach "tar: bad gzip magic". Toybox supports J/j/z/Z; pick by extension
/// rather than hoping auto-detect is present on every Android version.
@visibleForTesting
String tarCompressionFlag(String url) {
  final path = url.split('?').first.toLowerCase();
  if (path.endsWith('.tar.xz') || path.endsWith('.txz')) return 'J';
  if (path.endsWith('.tar.bz2') || path.endsWith('.tbz2')) return 'j';
  if (path.endsWith('.tar.zst') || path.endsWith('.tzst')) return 'Z';
  if (path.endsWith('.tar.gz') || path.endsWith('.tgz')) return 'z';
  // Uncompressed .tar, or something unknown — let tar try it bare rather
  // than asserting a codec it will choke on.
  return '';
}
