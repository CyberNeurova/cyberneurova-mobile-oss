import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter/foundation.dart';

import 'package:xterm/xterm.dart';

import 'package:cyberneurova_mobile/core/agent/device/pane_label.dart';
import 'package:cyberneurova_mobile/core/agent/device/pty_shell.dart';
import 'package:cyberneurova_mobile/core/agent/device/sticky_modifiers.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/shell_backend.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_scrollback.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/terminal_escapes.dart';
import 'package:cyberneurova_mobile/core/agent/device/background_runs.dart';

/// One pane — a single shell process with its own cwd and its own history.
///
/// This mirrors tmux exactly: a pane owns a process, and two panes in the same
/// session can sit in different directories. What is shared is *within* a
/// pane — the terminal and the agent both act on this pane's [shell] and both
/// write to this pane's [scrollback], which is the invariant from
/// `docs/shell/00-OVERVIEW.md` §1.
///
/// Nothing here is a widget. Panes outlive the screens that render them, which
/// is what makes detach/reattach work.
class ShellPane {
  ShellPane({
    required this.id,
    required this.title,
    required this.shell,
    this.backend,
    ShellScrollback? scrollback,
  }) : scrollback = scrollback ?? ShellScrollback();

  final String id;

  /// tmux-style label. Renameable.
  String title;

  final ShellSession shell;

  /// Android's shell, or a Linux distro under PRoot. Held on the pane so the
  /// agent's `shell_exec` and this pane's PTY cannot drift onto different
  /// filesystems.
  final ShellBackend? backend;
  final ShellScrollback scrollback;

  /// Ctrl/Alt armed for the next keystroke, shared between the extra-keys row
  /// that arms them and the write path that applies them.
  final StickyModifiers modifiers = StickyModifiers();

  PtyShellSession? _pty;
  StreamSubscription<void>? _ptySub;

  /// The real terminal — a character grid with colours, cursor addressing and
  /// alternate-screen support.
  ///
  /// The scrollback list this used to render could show command output and
  /// nothing else: `vi`, `nano`, `htop`, `less` and every other full-screen
  /// program needs a grid to draw into, and `ls --color` / `git diff` need
  /// SGR. For a product that promises a Linux environment, "you cannot open an
  /// editor" is the limit that makes it feel like a toy.
  ///
  /// [ShellScrollback] is kept alongside — it is now purely the MODEL's
  /// transcript. The two want opposite things: the terminal needs the raw
  /// escape stream to render, the model needs it stripped or it wastes context
  /// on bytes that mean nothing. Feeding both from one PTY stream is cheap and
  /// keeps each correct.
  late final Terminal terminal = Terminal(maxLines: 5000);

  PtyShellSession? get pty => _pty;
  bool get isRunning => _pty != null;

  /// True when [title] came from the user rather than the ordinal default.
  /// A name someone typed is never overridden by what happens to be running.
  bool userNamed = false;

  int? _exitCode;
  bool _startFailed = false;

  /// Honest lifecycle. `isRunning` collapses never-started, exited cleanly and
  /// died-with-an-error into one `false`, and a session list cannot render
  /// truthfully from that.
  PaneStatus get status {
    if (_pty != null) return PaneStatus.running;
    if (_startFailed) return PaneStatus.failed;
    if (_exitCode == null) return PaneStatus.idle;
    return _exitCode == 0 ? PaneStatus.exited : PaneStatus.failed;
  }

  /// The shell itself, for when nothing else is running in the pane.
  String get shellName {
    final label = backend?.label;
    if (label == null || label.isEmpty) return 'shell';
    // "Alpine Linux" -> "alpine": a tab is narrow and the distro's first word
    // is what identifies it.
    return label.split(RegExp(r'[\s/]')).first.toLowerCase();
  }

  /// What to call this pane, kept live so the switcher can watch it.
  late final ValueNotifier<String> label = ValueNotifier(_computeLabel());

  String? _foreground;
  Timer? _labelPoll;

  String _computeLabel() => paneLabel(
        userTitle: userNamed ? title : null,
        foreground: _foreground,
        shellName: shellName,
        status: status,
      );

  void _refreshLabel() {
    final next = _computeLabel();
    if (label.value != next) label.value = next;
  }

  /// Reads the shell's descendants out of `/proc` to find what it is running.
  ///
  /// Polled rather than pushed because there is no event for "the foreground
  /// process changed" — the shell forks without telling us. Two small file
  /// reads every second and a half is far cheaper than it sounds, and it stops
  /// entirely when the pane is not running.
  Future<void> _pollForeground() async {
    final pty = _pty;
    if (pty == null) {
      _foreground = null;
      _refreshLabel();
      return;
    }

    final chain = <String>[];
    var current = pty.pid;
    // Bounded: `git` -> `less` is two deep, and a runaway walk on a busy
    // process tree is not worth the battery.
    for (var depth = 0; depth < 6; depth++) {
      final kids = await _childrenOf(current);
      if (kids.isEmpty) break;
      // The newest child is the one in the foreground.
      final child = kids.last;
      final comm = await _commOf(child);
      if (comm == null) break;
      chain.add(comm);
      current = child;
    }

    _foreground = foregroundFromChain(chain);
    _refreshLabel();
  }

  Future<List<int>> _childrenOf(int pid) async {
    // The direct route, when the kernel was built with CONFIG_PROC_CHILDREN.
    try {
      final f = File('/proc/$pid/task/$pid/children');
      if (f.existsSync()) {
        return [
          for (final t in (await f.readAsString()).trim().split(RegExp(r'\s+')))
            if (int.tryParse(t) != null) int.parse(t),
        ];
      }
    } catch (_) {
      // Fall through — an unreadable /proc is not an error worth surfacing.
    }

    // Otherwise walk /proc looking for our own pid as a parent. Bounded to
    // numeric entries; hidepid means this only ever sees our processes.
    try {
      final out = <int>[];
      for (final e in Directory('/proc').listSync(followLinks: false)) {
        final base = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final child = int.tryParse(base);
        if (child == null) continue;
        try {
          final stat = File('/proc/$child/stat').readAsStringSync();
          if (ppidFromStat(stat) == pid) out.add(child);
        } catch (_) {
          // The process ended between listing and reading. Normal.
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _commOf(int pid) async {
    try {
      return (await File('/proc/$pid/comm').readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  /// Last geometry the view reported, so a pane started later comes up at the
  /// right size instead of at the 80x25 default and then reflowing.
  int _columns = 80;
  int _rows = 25;

  /// Starts the shell if it isn't already running.
  ///
  /// Idempotent — reattaching to a live pane must not spawn a second shell,
  /// which would fork the pane in two and break its single scrollback.
  void start({int? columns, int? rows}) {
    _columns = columns ?? _columns;
    _rows = rows ?? _rows;
    return _start(columns: _columns, rows: _rows);
  }

  void _start({required int columns, required int rows}) {
    if (_pty != null) return;
    if (!PtyShellSession.isSupported) {
      scrollback.appendSystem(
        'Interactive shell is not available on this platform. '
        'Use the agent, or connect a remote executor.',
      );
      return;
    }

    // A spawn failure must be visible. Previously an exception here left the
    // pane silently dead: no "started" line, no error, and the next typed
    // command answered "No shell is running" with no clue why — which is the
    // same invisible-failure trap as a swallowed command.
    final PtyShellSession pty;
    try {
      pty = PtyShellSession.start(shell,
          columns: columns, rows: rows, backend: backend);
    } catch (e) {
      scrollback.appendSystem(
        'Could not start ${backend?.label ?? "the shell"}: $e',
      );
      _startFailed = true;
      _refreshLabel();
      return;
    }
    _pty = pty;
    _startFailed = false;
    _exitCode = null;
    _labelPoll?.cancel();
    _labelPoll = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _pollForeground(),
    );
    _refreshLabel();

    // Keystrokes the user types INTO the grid go straight to the process.
    // This is what makes vi and htop usable — arrow keys, ctrl chords and
    // escape all reach the program instead of being interpreted by us.
    // Through the sticky modifiers, so a Ctrl armed on the extra-keys row
    // applies to the next key WHEREVER it was typed — including the system
    // keyboard, which never touches that row. Without this, Ctrl+X and
    // Ctrl+C are unreachable and a full-screen program cannot be left.
    terminal.onOutput = (data) => pty.write(modifiers.consume(data));
    // The grid owns its own size now, so it reports the real geometry rather
    // than the view guessing from font metrics.
    terminal.onResize = (w, h, pw, ph) => resize(rows: h, columns: w);

    scrollback.appendSystem(
        'Pane "$title" · ${backend?.label ?? "Android shell"} · ${shell.cwd}');

    // Decode as UTF-8, and do it through the STREAM decoder.
    //
    // `String.fromCharCodes` treats each byte as a code unit, so any non-ASCII
    // byte became a wrong character — that is what rendered as a run of tofu
    // boxes on device. A one-shot `utf8.decode` per chunk would be almost as
    // bad, because a PTY splits at arbitrary byte offsets and a multi-byte
    // sequence straddling two chunks would corrupt both. `Utf8Decoder.bind`
    // carries the partial sequence across chunk boundaries.
    _ptySub = const Utf8Decoder(allowMalformed: true)
        .bind(pty.output)
        .listen((chunk) {
      // RAW to the terminal — escapes intact. Stripping here is what made
      // colour and full-screen apps impossible.
      terminal.write(chunk);

      // Stripped here, not at render time: the scrollback is also the model's
      // transcript, and escape noise costs context and can be misread as
      // output. The PTY has already parsed the OSC 7 cwd out of these bytes
      // (pty_shell.dart), so nothing meaningful is lost.
      // The terminal handles `clear` itself now (it has a grid to erase), but
      // the model's transcript still needs trimming or the agent keeps reading
      // output the user has deliberately cleared away.
      var body = chunk;
      final eraseEnd = lastEraseDisplayEnd(chunk);
      if (eraseEnd >= 0) {
        debugPrint('[scrollback] erase-display cleared '
            '${scrollback.length} lines '
            'sb=${identityHashCode(scrollback)}');
        scrollback.clear();
        body = chunk.substring(eraseEnd);
      }

      final text = stripTerminalEscapes(body);
      if (text.isEmpty) return;
      // appendStream, not append: PTY chunks are split at arbitrary bytes and
      // a chunk boundary is not a line boundary.
      scrollback.appendStream(text, source: ShellLineSource.user);
    }, onDone: () {
      scrollback.appendSystem('Shell exited.');
      _pty = null;
      _onStopped();
    });

    pty.exitCode.then((code) {
      scrollback.appendSystem('Shell exited with status $code.');
      _pty = null;
      _exitCode = code;
      _onStopped();
    }).catchError((_) {});
  }

  void _onStopped() {
    _labelPoll?.cancel();
    _labelPoll = null;
    _foreground = null;
    _refreshLabel();
  }

  void runUserCommand(String command) {
    final pty = _pty;
    if (pty == null) {
      // Never swallow it. A terminal that shows your command and then does
      // nothing is indistinguishable from one that ran it and printed no
      // output — you'd read the empty result as the answer.
      scrollback.appendCommand(command, source: ShellLineSource.user);
      scrollback.appendSystem(
        'No shell is running in this pane — start it to run commands.',
      );
      return;
    }
    // No local echo: the PTY echoes what we write, so appending here too
    // printed every typed command twice. The shell's own prompt + echo is
    // what a terminal looks like, and it is the truthful record — it shows
    // what the shell received, not what we hoped it received.
    pty.write('$command\n');
  }

  /// Records a command the AGENT ran into this pane's history.
  ///
  /// The agent's one-shot `shell_exec` deliberately does NOT go through the
  /// PTY: injecting into an interactive stream would race with whatever the
  /// user is typing. It runs as its own process against the same cwd/env and
  /// reports here — unified history, separate stdin.
  void recordAgentCommand(String command, String output, {bool ok = true}) {
    // Echo into the grid as well, dimmed and marked, so someone watching the
    // terminal sees the agent working rather than only finding it later in
    // the model's transcript.
    //
    // CRLF, not LF: a PTY grid moves the cursor DOWN on a newline but does
    // not return it to column 0, so bare \n stair-steps output
    // diagonally across the screen.
    terminal.write('\x1b[2m[agent]\x1b[0m $command\r\n');
    if (output.isNotEmpty) {
      terminal.write('${output.replaceAll('\n', '\r\n')}\r\n');
    }
    scrollback.appendCommand(command, source: ShellLineSource.agent);
    if (output.isNotEmpty) {
      scrollback.append(output, source: ShellLineSource.agent);
    }
    if (!ok) scrollback.appendSystem('(command failed)');
  }

  /// Tells the shell how big the terminal actually is.
  ///
  /// **Not cosmetic.** The PTY was created 80×25 and never told otherwise,
  /// while a phone in mono at 12.5sp is nearer 40 columns. mksh's line editor
  /// believes the width it is given, so as soon as a command exceeded the
  /// imaginary 80 columns it emitted cursor-movement and redraw sequences to
  /// scroll a line that was not actually there — which is what produced the
  /// `<` marker and the run of unrenderable glyphs on device.
  /// Timer coalescing PTY resizes; see [resize].
  Timer? _resizeDebounce;

  void resize({required int rows, required int columns}) {
    if (columns == _columns && rows == _rows) return;
    _columns = columns;
    _rows = rows;

    // Debounce the PTY notification.
    //
    // The grid re-measures every frame while the soft keyboard animates, so a
    // single keyboard open used to deliver a dozen SIGWINCHes to the guest.
    // A full-screen program redraws for each one, and nano visibly drew its
    // help bar against sizes that had already changed — landing it mid-screen,
    // then off it entirely — while losing keystrokes it was too busy to read.
    // Typing at a plain prompt was always lossless, which is what pointed here
    // rather than at the write path.
    //
    // Our own grid still resizes immediately; only the guest waits, and it
    // waits for the size that will still be true when it redraws.
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 140), () {
      _pty?.resize(rows: _rows, columns: _columns);
    });
  }

  Future<void> dispose() async {
    _resizeDebounce?.cancel();
    await _ptySub?.cancel();
    await _pty?.kill();
    _pty = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    await scrollback.dispose();
  }
}

/// One workspace — the tmux *session*: an ordered set of panes plus which one
/// is focused.
///
/// Splitting is modelled as a flat, ordered list rather than a layout tree on
/// purpose. On a phone only one pane is realistically visible at a time, so
/// the useful operations are "next/previous/select", not "split 30/70
/// horizontally". A layout tree can be layered on later for tablets without
/// changing this API.
class ShellWorkspace {
  ShellWorkspace({
    required this.id,
    required this.name,
    required this.rootDir,
    Map<String, String>? baseEnv,
    this.backend,
  }) : baseEnv = Map.unmodifiable({...?baseEnv}) {
    sessionDir = _ensureSessionDir();
    newPane(); // a session always has at least one pane
  }

  /// This session's own directory, as a guest path.
  ///
  /// ## Why sessions need their own directory
  ///
  /// Every session used to start in the same home, so one `ls` showed six
  /// artefacts from four unrelated sessions in a single flat pile — a snake
  /// game, a scan report and someone's scratch file, indistinguishable.
  /// Nothing could be described as "the project", because there was no place
  /// a project could be.
  ///
  /// A session directory makes the obvious thing work: the agent runs `mkdir
  /// snake-game` and it lands somewhere that belongs to this conversation,
  /// beside the other things this conversation built and nothing else.
  ///
  /// Named from the first eight characters of the chat id rather than the
  /// whole thing: stable across restarts (the session name counter is not),
  /// unique in practice, and short enough that the prompt stays readable on a
  /// phone — `~/sessions/94d27346` rather than a full UUID.
  late final String sessionDir;

  /// The things this session has built.
  ///
  /// A project is simply a directory in the session's own directory — no
  /// manifest, no registry, no convention the model has to be taught. The
  /// agent runs `mkdir snake-game` because that is what anyone would do, and
  /// it becomes a project by virtue of being there. A scheme that needed the
  /// model to declare a project would be a scheme the model forgets to use.
  ///
  /// Read from disk on each call rather than cached: the shell and the agent
  /// both create directories behind our back, which is the point.
  List<SessionProject> projects() {
    final host = backend?.toHostPath(sessionDir) ?? sessionDir;
    final dir = Directory(host);
    if (!dir.existsSync()) return const [];

    final out = <SessionProject>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = _basename(e.path);
        // Hidden directories are the environment's business, not the user's —
        // `.cache`, `.config` and friends are not projects.
        if (name.startsWith('.')) continue;
        out.add(SessionProject(
          name: name,
          path: p.posix.join(sessionDir, name),
          fileCount: _countEntries(e),
          modified: e.statSync().modified,
        ));
      }
    } catch (_) {
      return const [];
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// Writes [content] into this session as [name], returning the guest path.
  ///
  /// This exists because the model does not always call `file_write`. Asked to
  /// build a page, a 12B model will often print it as a fenced code block and
  /// declare itself done — the answer is right there and completely useless,
  /// because the surface's whole promise is a real file on the phone. Rather
  /// than leave the user copying code out of a chat bubble by hand, the block
  /// itself offers to become the file the model should have written.
  ///
  /// Lands in the pane's current directory, so it appears where the user is
  /// actually standing when they `ls`. [name] is treated as a leaf: a path
  /// separator in it would let a reply written by the model choose where on
  /// the filesystem to land.
  String saveFile(String name, String content) {
    final leaf = _basename(name.replaceAll('\\', '/')).trim();
    if (leaf.isEmpty || leaf == '.' || leaf == '..') {
      throw ArgumentError('Not a usable file name: $name');
    }
    final cwd = active.shell.cwd;
    final guest = p.posix.join(cwd, leaf);
    final host = backend?.toHostPath(guest) ?? guest;
    final file = File(host);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return guest;
  }

  static int _countEntries(Directory d) {
    try {
      return d.listSync(followLinks: false).length;
    } catch (_) {
      return 0;
    }
  }

  String _ensureSessionDir() {
    final base = backend?.initialCwd ?? rootDir;
    final slug = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final short = slug.length > 8 ? slug.substring(0, 8) : slug;
    final guest = p.posix.join(base, 'sessions', short.isEmpty ? 'default' : short);

    // Created eagerly. A cwd that does not exist makes the shell start in an
    // unpredictable place and every relative path in the session wrong, which
    // is worse than the cost of one mkdir.
    try {
      Directory(backend?.toHostPath(guest) ?? guest).createSync(recursive: true);
    } catch (_) {
      // A read-only or missing root is not worth failing the session over —
      // the shell still starts, just in the home directory.
      return base;
    }
    return guest;
  }

  final String id;

  /// User-facing session name.
  ///
  /// Defaults to the ordinal (`shell-3`), which says nothing about what the
  /// session is for — with four open, the list is four numbers. [displayName]
  /// prefers the conversation's own title once it has one, the same way the
  /// chat list names itself.
  String name;

  /// The title the conversation has earned, or the ordinal until it has one.
  ///
  /// Set from the chat's title, which the server derives from the first
  /// exchange. Held here rather than looked up so the registry — which has no
  /// idea what a chat is — can still render a readable list.
  String? title;

  /// What to call this session in the UI.
  String get displayName {
    final t = title?.trim();
    if (t == null || t.isEmpty) return name;
    // "New Chat" is the server's placeholder, not a name anybody chose.
    if (t.toLowerCase() == 'new chat') return name;
    return t;
  }

  /// Sandbox root shared by every pane in this session.
  final String rootDir;

  /// Environment every pane starts with — chiefly `PATH` and `PREFIX` from
  /// [PrefixBootstrap], so a bundled tool resolves by name in a new pane just
  /// as it does in the first one. Per-pane `setEnv` diverges from here; that's
  /// intended, panes are independent processes.
  final Map<String, String> baseEnv;

  /// The shell every pane in this session runs on. Per workspace, not per
  /// pane: two panes of one session on different filesystems would be a trap.
  final ShellBackend? backend;

  final List<ShellPane> _panes = [];
  int _activeIndex = 0;
  int _paneCounter = 0;

  List<ShellPane> get panes => List.unmodifiable(_panes);
  int get paneCount => _panes.length;
  int get activeIndex => _activeIndex;

  /// The focused pane. Never null — closing the last pane creates a fresh one
  /// rather than leaving a session with nothing in it.
  ShellPane get active => _panes[_activeIndex];

  // Convenience passthroughs so callers that only care about "the current
  // shell" (the agent's tools, mostly) don't have to reach through .active.
  ShellSession get shell => active.shell;
  ShellScrollback get scrollback => active.scrollback;

  /// Adds a pane and focuses it — tmux `split-window`.
  ///
  /// The new pane inherits the current pane's working directory, which is what
  /// tmux does with `-c "#{pane_current_path}"` and what anyone splitting a
  /// terminal actually expects: you split to run a second thing *here*.
  ShellPane newPane({String? title, bool inheritCwd = true}) {
    _paneCounter++;
    // A new pane starts where the current one is, or in the session's own
    // directory — never in the shared home, which is what put every session's
    // output in one pile.
    final cwd = (inheritCwd && _panes.isNotEmpty) ? active.shell.cwd : sessionDir;
    final b = backend;
    final pane = ShellPane(
      id: '$id:$_paneCounter',
      title: title ?? 'pane $_paneCounter',
      backend: b,
      shell: ShellSession(
        // Under PRoot these are GUEST paths: root is `/`, home is `/root`.
        rootDir: b?.rootDir ?? rootDir,
        cwd: cwd,
        // Home is where the backend starts, NOT the sandbox root — a new pane
        // that inherited another's cwd must still send `~` to the right place.
        homeDir: b?.initialCwd ?? rootDir,
        env: baseEnv,
        toHostPath: b?.toHostPath,
        enforceContainment: b?.enforceHostContainment ?? true,
      ),
    );
    _panes.add(pane);
    _activeIndex = _panes.length - 1;
    return pane;
  }

  ShellPane? paneById(String paneId) {
    for (final p in _panes) {
      if (p.id == paneId) return p;
    }
    return null;
  }

  void selectPane(int index) {
    if (index < 0 || index >= _panes.length) return;
    _activeIndex = index;
  }

  bool selectPaneById(String paneId) {
    final i = _panes.indexWhere((p) => p.id == paneId);
    if (i < 0) return false;
    _activeIndex = i;
    return true;
  }

  /// tmux `select-pane -t :.+` — wraps around.
  void nextPane() {
    if (_panes.isEmpty) return;
    _activeIndex = (_activeIndex + 1) % _panes.length;
  }

  void previousPane() {
    if (_panes.isEmpty) return;
    _activeIndex = (_activeIndex - 1 + _panes.length) % _panes.length;
  }

  /// Closes a pane and keeps the focus sane.
  ///
  /// Closing the LAST pane doesn't leave an empty session — it opens a fresh
  /// one, so "close pane" can never strand the user on a blank screen.
  Future<void> closePane(String paneId) async {
    final i = _panes.indexWhere((p) => p.id == paneId);
    if (i < 0) return;
    final pane = _panes.removeAt(i);
    await pane.dispose();

    if (_panes.isEmpty) {
      newPane();
      return;
    }
    // Focus the neighbour, the way a multiplexer does, rather than jumping to 0.
    _activeIndex = i.clamp(0, _panes.length - 1);
  }

  Future<void> dispose() async {
    for (final p in _panes) {
      await p.dispose();
    }
    _panes.clear();
  }
}

/// Every open workspace — the tmux *server*.
///
/// Lives above the widget tree so sessions outlive the screens that display
/// them: that is the difference between a terminal feature and a multiplexer.
class ShellWorkspaceRegistry {
  ShellWorkspaceRegistry({
    required this.rootDir,
    Map<String, String>? baseEnv,
    this.backendOf,
  }) : baseEnv = Map.unmodifiable({...?baseEnv});

  /// Read lazily, when a workspace is created — NOT captured up front.
  ///
  /// The backend depends on a future (is a distro installed?). If the registry
  /// took it by value it would be rebuilt when that future resolved, and the
  /// rebuild disposes every workspace — killing live shells out from under the
  /// user. Reading it per workspace also means installing a distro applies to
  /// the next shell without disturbing the ones already open.
  final ShellBackend? Function()? backendOf;

  final String rootDir;

  /// Handed to every workspace this registry creates — see
  /// [ShellWorkspace.baseEnv].
  final Map<String, String> baseEnv;

  final Map<String, ShellWorkspace> _byId = {};
  int _counter = 0;

  List<ShellWorkspace> get all => List.unmodifiable(_byId.values);

  ShellWorkspace? byId(String id) => _byId[id];

  ShellWorkspace create({required String id, String? name}) {
    final existing = _byId[id];
    if (existing != null) return existing;

    _counter++;
    final ws = ShellWorkspace(
      id: id,
      name: name ?? 'shell-$_counter',
      rootDir: rootDir,
      baseEnv: baseEnv,
      backend: backendOf?.call(),
    );
    _byId[id] = ws;
    _publishSessionCount();
    return ws;
  }

  /// Removes a session, and optionally the work it produced.
  ///
  /// The two are separated on purpose. Closing a conversation and destroying
  /// the only copy of what it built are very different intentions, and a
  /// phone is often the only place that work exists — there is no second
  /// machine it was synced to. So the caller has to say which it means, and
  /// [keepFiles] is the answer that loses nothing.
  Future<void> remove(String id, {required bool keepFiles}) async {
    final ws = _byId.remove(id);
    if (ws == null) return;
    await ws.dispose();

    if (!keepFiles) {
      final host = ws.backend?.toHostPath(ws.sessionDir) ?? ws.sessionDir;
      try {
        final dir = Directory(host);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {
        // A file the shell still holds open is not worth failing the delete
        // over — the session is gone from the list either way.
      }
    }
    _publishSessionCount();
  }

  /// Moves work from before sessions existed into one of its own.
  ///
  /// Every session used to write into the shared home, so an upgrade would
  /// otherwise leave those files sitting outside every session — present on
  /// disk, absent from the app, indistinguishable from data loss to anyone
  /// who put real work there.
  ///
  /// Returns how many entries were moved. Idempotent: with nothing loose in
  /// the home there is nothing to do, so a second run is a no-op rather than
  /// something that needs a flag to guard it.
  int migrateLegacyFiles({String? homeOverride}) {
    final backend = backendOf?.call();
    final guestHome = homeOverride ?? backend?.initialCwd ?? rootDir;
    final host = backend?.toHostPath(guestHome) ?? guestHome;

    final home = Directory(host);
    if (!home.existsSync()) return 0;

    final legacyGuest = p.posix.join(guestHome, 'sessions', 'legacy');
    final legacyHost = backend?.toHostPath(legacyGuest) ?? legacyGuest;

    var moved = 0;
    try {
      for (final e in home.listSync(followLinks: false)) {
        final name = _basename(e.path);
        // `sessions` is the new home for all of this; moving it into itself
        // would be a loop, and dotfiles are the environment's own state.
        if (name == 'sessions' || name.startsWith('.')) continue;

        Directory(legacyHost).createSync(recursive: true);
        final target = '$legacyHost/$name';
        if (FileSystemEntity.typeSync(target) !=
            FileSystemEntityType.notFound) {
          continue; // already migrated under the same name; never overwrite
        }
        e.renameSync(target);
        moved++;
      }
    } catch (_) {
      return moved;
    }
    return moved;
  }

  /// Get-or-create — the reattach path.
  ShellWorkspace attach(String id, {String? name}) =>
      _byId[id] ?? create(id: id, name: name);

  Future<void> kill(String id) async {
    final ws = _byId.remove(id);
    _publishSessionCount();
    await ws?.dispose();
  }

  Future<void> killAll() async {
    for (final ws in _byId.values.toList()) {
      await ws.dispose();
    }
    _byId.clear();
    _publishSessionCount();
  }

  /// Tells the platform side how many sessions are alive.
  ///
  /// This is what stops Android from reclaiming the process and taking every
  /// open shell down with it — the multiplexer promise is worth nothing if the
  /// server dies whenever the user checks a message. It asks only for
  /// residency, never for the CPU: see [BackgroundRuns].
  void _publishSessionCount() =>
      BackgroundRuns.instance.setSessions(_byId.length);
}

/// One thing a session built — a directory inside the session's directory.
///
/// Deliberately not a stored record. The filesystem already is the source of
/// truth, and a parallel list would drift the first time the user or the agent
/// renamed something in the shell.
class SessionProject {
  const SessionProject({
    required this.name,
    required this.path,
    required this.fileCount,
    required this.modified,
  });

  final String name;

  /// Guest path, so it can be handed straight to the shell or a file tool.
  final String path;

  final int fileCount;
  final DateTime modified;

  String get summary =>
      '$fileCount ${fileCount == 1 ? 'file' : 'files'}';
}

/// Last path segment, whichever separator produced it.
///
/// `p.posix.basename` is wrong here and `p.basename` is worse: these paths
/// cross a guest/host boundary, so one side is always POSIX while the other
/// follows whatever the tests happen to run on.
String _basename(String path) {
  final slash = path.lastIndexOf('/');
  final back = path.lastIndexOf(r'\');
  final cut = slash > back ? slash : back;
  return cut < 0 ? path : path.substring(cut + 1);
}
