import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;

import 'package:cyberneurova_mobile/core/agent/device/linux/shell_backend.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';

/// An interactive PTY bound to a [ShellSession].
///
/// This is the *terminal path* of `docs/shell/00-OVERVIEW.md` §1. `shell_exec`
/// (the agent path) and this both run against the same [ShellSession], which
/// is what makes the invariant real:
///
/// > the terminal and the agent share one session, one working directory,
/// > one environment, one scrollback.
///
/// **Android only.** `flutter_pty` wraps `forkpty` and has no iOS backend —
/// and could not have one, since iOS forbids executing anything but the
/// signed app binary (`docs/shell/03-IOS-RUNTIME.md`). [isSupported] is the
/// check callers should branch on; iOS gets the built-in command router
/// instead.
///
/// Deliberately holds **no** UI: this class produces bytes and consumes bytes.
/// A terminal renderer (xterm.dart) attaches later without this file changing.
class PtyShellSession {
  PtyShellSession._(this._pty, this.session) {
    _outSub = _pty.output.listen(
      (data) {
        _watchCwd(data);
        _outController.add(data);
      },
      onDone: _outController.close,
      onError: _outController.addError,
    );
    _pty.exitCode.then((code) {
      if (!_exit.isCompleted) _exit.complete(code);
    });
  }

  /// Whether an interactive PTY can run on this platform at all.
  static bool get isSupported => Platform.isAndroid;

  /// The shell to spawn. `/system/bin/sh` is present on every Android device
  /// and brings ~210 toybox applets with it — verified on Android 16, see
  /// `docs/shell/SPIKE-RESULTS.md`. No bundled binary required.
  static const String androidShell = '/system/bin/sh';

  final Pty _pty;
  final ShellSession session;

  final _outController = StreamController<Uint8List>.broadcast();
  final _exit = Completer<int>();
  StreamSubscription<Uint8List>? _outSub;

  /// Raw PTY output. Escape sequences are left intact — the renderer needs
  /// them, and stripping here would break colour, cursor moves and resize.
  Stream<Uint8List> get output => _outController.stream;

  /// The shell's process id, used to find what it is currently running.
  ///
  /// Reading `/proc` under this pid is how a pane learns it is showing `nano`
  /// rather than a prompt. Android mounts `/proc` with `hidepid`, so this only
  /// ever reaches our own processes — which is the set we want anyway.
  int get pid => _pty.pid;

  Future<int> get exitCode => _exit.future;

  /// Starts a login-ish shell in the session's cwd with its env.
  ///
  /// Throws [UnsupportedError] on platforms without a PTY so a caller that
  /// forgot [isSupported] fails loudly rather than silently doing nothing.
  static PtyShellSession start(
    ShellSession session, {
    int columns = 80,
    int rows = 25,
    ShellBackend? backend,
  }) {
    if (!isSupported) {
      throw UnsupportedError(
        'Interactive PTY is not available on ${Platform.operatingSystem}. '
        'iOS cannot execute a shell — use the built-in command router or a '
        'remote executor.',
      );
    }

    // A PRoot backend spawns the GUEST's shell instead of Android's, and its
    // rc-file trick does not apply: the guest has its own /etc/profile and its
    // own prompt. Only the Android path gets `$ENV`.
    final isGuest = backend != null && !backend.enforceHostContainment;
    final pty = Pty.start(
      backend?.executable ?? androidShell,
      // Start where the SESSION is, not where the backend's home happens to
      // be. Without this the grid opened in /root while the model's cwd was
      // the session directory — the terminal and the agent looking at two
      // different places, which is the one thing this surface must not do.
      arguments: backend?.interactiveArgs(workingDir: session.cwd) ?? const [],
      environment: {
        ...Platform.environment,
        ...?backend?.environment(),
        // Host paths mean NOTHING inside a guest rootfs, and letting them
        // through is fatal rather than untidy. `prefix.env` carries a PATH
        // built for Android — our prefix plus /system/bin, /apex/… — and it
        // was landing on top of the guest's own PATH. Inside Kali none of
        // those directories exist, so /etc/profile could not even run `id`,
        // failed its root test, and never set PATH at all. Every session
        // opened with "id: not found" and nothing on PATH thereafter.
        //
        // Per-pane vars still win; only the three that describe a filesystem
        // layout are dropped, and only for a guest.
        ...(isGuest ? hostOnlyStripped(session.env) : session.env),
        if (backend == null) ...{
          // Android's sh has no sane defaults for these and tools misbehave
          // without them.
          'TERM': 'xterm-256color',
          'HOME': session.rootDir,
          // Scratch goes in the prefix, so a tool that litters temp files does
          // not litter the user's working directory.
          'TMPDIR': _tmpDir(session),
        },
        // Our init file, sourced by mksh at startup. This is what installs
        // the cwd-reporting prompt — see _writeRcFile. Meaningless to a guest
        // distro, which brings its own shell and its own startup files.
        if (!isGuest) 'ENV': _writeRcFile(session),
      },
      // PRoot is told the guest cwd via --cwd; the PROCESS starts wherever we
      // happen to be, and handing it a guest path here would fail to chdir.
      workingDirectory: isGuest ? null : session.cwd,
      columns: columns,
      rows: rows,
    );

    return PtyShellSession._(pty, session);
  }

  static String _tmpDir(ShellSession session) {
    final base = session.env['PREFIX'] ?? session.rootDir;
    final tmp = Directory(p.join(base, 'tmp'));
    if (!tmp.existsSync()) tmp.createSync(recursive: true);
    return tmp.path;
  }

  /// Writes the shell init file and returns its path, for `$ENV`.
  ///
  /// **Why this exists instead of just setting `PS1`.** We used to pass
  /// `PS1` in the environment. It never took effect: Android's
  /// `/system/etc/mkshrc` *assigns* `PS1` while initialising, so the shell
  /// came up with the stock `:/data/…/shell $` prompt and our OSC 7 sequence
  /// was never emitted — which silently disabled [_watchCwd] and with it the
  /// shared-cwd half of the `00-OVERVIEW.md` §1 invariant. Typing `cd` in the
  /// terminal left the agent pointed at the old directory. Verified on device
  /// by the prompt that appeared.
  ///
  /// mksh sources `$ENV` at startup, so we point it at our own file, source
  /// the system one first (keeping Android's aliases and functions), and set
  /// `PS1` afterwards so ours is the assignment that survives.
  ///
  /// The prompt is `OSC 7 <cwd> BEL` followed by `$ `. Written as real control
  /// bytes because mksh does not expand bash's `\e`/`\a` in `PS1`. `$PWD` is
  /// single-quoted deliberately — mksh expands `PS1` each time it prints, so
  /// this reports the *current* directory, not the one at startup.
  static String _writeRcFile(ShellSession session) {
    // Into the prefix, never the working directory. `ls` on a fresh session
    // must show the user's files and nothing of ours — a stray `.cnrc` in
    // `~` is exactly the noise this design is trying to avoid.
    final etc = Directory(p.join(session.env['PREFIX'] ?? session.rootDir, 'etc'));
    if (!etc.existsSync()) etc.createSync(recursive: true);
    final path = p.join(etc.path, 'cnrc');
    const esc = '\x1b';
    const bel = '\x07';
    File(path).writeAsStringSync(
      '# CyberNeurova shell init — generated, edits are overwritten.\n'
      '[ -r /system/etc/mkshrc ] && . /system/etc/mkshrc\n'
      "PS1='$esc]7;\$PWD$bel\$ '\n"
      '\n$_guards',
      flush: true,
    );
    return path;
  }

  /// Makes the shell explain itself instead of saying "not found".
  ///
  /// `apt` is the single most common thing a person types here, and the honest
  /// answer is not "command not found" — it is *"this is Android's own shell,
  /// there is no distribution underneath it, and there never was a package
  /// manager to find"*. A bare 127 leaves the user (and the model) assuming
  /// something is broken and retrying, which is exactly the loop
  /// `DeviceCapabilities` exists to prevent — this is the same idea applied to
  /// the human half of the session.
  ///
  /// Aliases rather than functions because `apt-get` and `add-apt-repository`
  /// are not valid function names everywhere, and aliases accept any word.
  /// They only expand in an interactive shell, which is precisely the case
  /// that has a human reading the output; the agent gets the same information
  /// up front from its capability block.
  static const String _guards = r'''
cn_no_pkg() {
  echo "$1: not available — this is Android's own shell (toybox + mksh)," >&2
  echo "not a Linux distribution. There is no apt/apk/yum here and no root," >&2
  echo "so there is nothing for a package manager to install into." >&2
  echo "" >&2
  echo "Type 'cn-tools' to see what this shell can actually do." >&2
  return 127
}
alias apt='cn_no_pkg apt'
alias apt-get='cn_no_pkg apt-get'
alias aptitude='cn_no_pkg aptitude'
alias apk='cn_no_pkg apk'
alias yum='cn_no_pkg yum'
alias dnf='cn_no_pkg dnf'
alias pacman='cn_no_pkg pacman'
alias brew='cn_no_pkg brew'
alias npm='cn_no_pkg npm'
alias pip='cn_no_pkg pip'
alias pip3='cn_no_pkg pip3'
alias sudo='cn_no_pkg sudo'
alias su='cn_no_pkg su'

cn-tools() {
  echo "CyberNeurova shell — what you have here:"
  echo ""
  echo "  Shell     mksh (/system/bin/sh)"
  echo "  Tools     Android's toybox — ls cat grep sed awk find tar"
  echo "            nc ps netstat ping wget vi and ~200 more."
  echo "            Run 'toybox' for the full list."
  echo "  Home      $HOME  (yours; starts empty)"
  echo "  Prefix    $PREFIX (ours: bundled tools land in \$PREFIX/bin)"
  echo ""
  echo "What you CANNOT do, and why:"
  echo "  - install packages: no distribution, no package manager, no root."
  echo "  - run a binary you downloaded: Android blocks executing files an"
  echo "    app wrote to its own storage (SELinux, since Android 10)."
  echo "  - read /system/bin or other apps' data: not permitted without root."
  echo ""
  echo "Switch the input to Ask to have the agent work in this same shell."
}
alias cn_tools=cn-tools
''';

  /// Feeds user keystrokes (or agent-typed text) into the shell.
  void write(String data) => _pty.write(const Utf8Encoder().convert(data));

  void writeBytes(Uint8List data) => _pty.write(data);

  /// Must be called when the visible grid changes, or full-screen programs
  /// (vi, top) render into the wrong box.
  void resize({required int rows, required int columns}) =>
      _pty.resize(rows, columns);

  Future<void> kill() async {
    _pty.kill();
    await _outSub?.cancel();
    if (!_outController.isClosed) await _outController.close();
  }

  // ── cwd tracking ──────────────────────────────────────────────────────────

  /// Buffer for OSC 7 sequences split across reads. PTY output arrives in
  /// arbitrary chunks, so the escape can straddle a boundary.
  String _pending = '';

  /// Matches the OSC 7 "current directory" report: `ESC ] 7 ; <path> BEL`.
  ///
  /// This is the standard mechanism terminal emulators use to follow a
  /// shell's cwd, which is why the PS1 above emits it. Parsing output is the
  /// only way — a child process's chdir is invisible to the parent.
  static final _osc7 = RegExp(r'\x1b\]7;([^\x07\x1b]*)(?:\x07|\x1b\\)');

  void _watchCwd(Uint8List data) {
    _pending += utf8.decode(data, allowMalformed: true);
    // Keep the tail bounded — a long-running `cat` of a big file must not
    // grow this without limit.
    if (_pending.length > 4096) {
      _pending = _pending.substring(_pending.length - 4096);
    }

    String? last;
    for (final m in _osc7.allMatches(_pending)) {
      last = m.group(1);
    }
    if (last == null || last.isEmpty) return;
    _pending = '';

    // Strip the `file://host` prefix some shells emit.
    var path = last;
    if (path.startsWith('file://')) {
      final idx = path.indexOf('/', 'file://'.length);
      path = idx >= 0 ? path.substring(idx) : path;
    }

    // Route through the session so the SAME sandbox check applies as `cd`.
    // If the user cd'd outside the session root the shell moves but our
    // recorded cwd deliberately does not — the agent must never be handed a
    // path it isn't allowed to operate on.
    session.changeDirectory(path);
  }
}

/// Session vars that describe the HOST filesystem, dropped for guest shells.
///
/// PATH, PREFIX and LD_LIBRARY_PATH all point at directories that exist on
/// Android and not inside a rootfs. Passing them to a guest silently breaks
/// command resolution for everything.
/// Drops the three variables that describe a HOST filesystem layout.
///
/// Shared with `shell_exec` deliberately. Both spawn a process inside the
/// guest, both start from the pane's env, and both are fatal if the Android
/// `PATH` survives the crossing — none of those directories exist in the
/// rootfs, so every command comes back `exit 127`. Fixing it in one place and
/// not the other is exactly what happened: the terminal worked and the agent's
/// shell reported "ls: not found" for a day.
Map<String, String> hostOnlyStripped(Map<String, String> env) {
  const hostOnly = {'PATH', 'PREFIX', 'LD_LIBRARY_PATH'};
  return {
    for (final e in env.entries)
      if (!hostOnly.contains(e.key)) e.key: e.value,
  };
}
