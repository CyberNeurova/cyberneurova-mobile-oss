import 'package:cyberneurova_mobile/shared/format/byte_size.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' show Terminal;
import 'package:go_router/go_router.dart';

import 'package:cyberneurova_mobile/core/routing/safe_pop.dart';

import 'package:cyberneurova_mobile/core/agent/device/shell_scrollback.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_workspace.dart';
import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/attachments_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/model_picker.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/agent_activity_strip.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/ask_status_strip.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/ask_view.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/extra_keys_row.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/pane_switcher.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/shell_terminal_view.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/shell_input_bar.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/shell_sessions_drawer.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/screens/file_viewer_screen.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/widgets/file_browser_drawer.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/screens/agent_browser_screen.dart';

/// The Shell workspace — a terminal you can also talk to.
///
/// Layout, top to bottom:
///
/// ```
///  ── app bar ──────────────  ☰ shells · session name · cwd
///  ── pane strip ───────────  tmux tabs, running dots, +
///  ── console ──────────────  the SHARED scrollback (you + agent), TOP-anchored
///  ── extra keys ───────────  only while typing a command
///  ── input ────────────────  [Run | Ask] one field, explicit mode
/// ```
///
/// The console is the shared surface: what you type and what the agent runs
/// both land there, marked by provenance (`shell_console_view.dart`). That
/// is the `00-OVERVIEW.md` §1 invariant made visible — it is the whole
/// premise of the feature, so it gets the screen's entire middle.
///
/// **Why one input with a mode, rather than two screens.** Run and Ask act on
/// the same session, the same directory and the same history. Putting the
/// agent behind a separate "AI shell" screen would imply a second context and
/// invite the user to wonder which directory it is in — the answer is always
/// "this one". A toggle keeps that obvious.
///
/// **Why the console is top-anchored.** A terminal fills downward from the
/// top. Bottom-anchoring (the chat convention) floats three lines of output at
/// the bottom of an empty screen, and shifts the entire buffer every time the
/// keyboard opens. Top-anchored, opening the keyboard just shortens the
/// viewport and nothing moves.
class ShellSessionScreen extends ConsumerStatefulWidget {
  const ShellSessionScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ShellSessionScreen> createState() => _ShellSessionScreenState();
}

class _ShellSessionScreenState extends ConsumerState<ShellSessionScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  /// Run (straight to the shell) or Ask (plain language to the agent).
  ///
  /// Held per screen rather than per pane: it describes how *you* are working
  /// right now, not a property of the process.
  ShellInputMode _mode = ShellInputMode.run;

  /// Scrollback revision at the moment we last left Shell.
  ///
  /// Both halves of a session keep running when you switch — the PTY is held
  /// above the widget tree and the IndexedStack keeps Ask mounted — so the
  /// only thing ever missing was knowing that they had. Comparing against the
  /// revision at departure answers "did the shell do anything while I was in
  /// Ask?" without polling or a second stream.
  int _shellRevisionOnLeave = 0;

  /// Focus for the terminal GRID, as opposed to the command bar.
  final _terminalFocus = FocusNode();

  /// Whether the terminal grid currently owns the keyboard.
  ///
  /// Typing straight into the grid already worked — xterm takes focus on tap
  /// and routes keys to the PTY — but nothing said so, and with a command bar
  /// sitting right below it the natural assumption is that the bar is the only
  /// way in. Tracking focus lets the bar step back and admit it.
  bool _terminalHasFocus = false;

  /// True while a full-screen program owns the screen (vi, htop, less).
  ///
  /// Detected from the terminal's alternate buffer — the same signal the
  /// program itself uses to say "I am taking over the display". While it is
  /// up, the command bar is meaningless (there is no prompt to type at) and
  /// the program needs raw keys, so focus and the keyboard belong to the grid.
  bool _fullscreen = false;
  Terminal? _watchedTerminal;

  void _watchFullscreen(Terminal t) {
    if (identical(_watchedTerminal, t)) return;
    _watchedTerminal?.removeListener(_onTerminalChanged);
    _watchedTerminal = t..addListener(_onTerminalChanged);
  }

  void _onTerminalChanged() {
    final t = _watchedTerminal;
    if (t == null || !mounted) return;
    if (t.isUsingAltBuffer == _fullscreen) return;
    setState(() => _fullscreen = t.isUsingAltBuffer);
    // Hand the keyboard over, and take it back when the program exits.
    if (_fullscreen) {
      _inputFocus.unfocus();
      _terminalFocus.requestFocus();
    } else {
      _terminalFocus.unfocus();
    }
  }

  /// Panes we've already auto-started, by id.
  ///
  /// A workspace is created with one pane but no process — the registry builds
  /// it outside the widget tree and has no business spawning a shell nobody is
  /// looking at yet. Opening the screen is what makes a pane worth running, so
  /// that's where it starts.
  ///
  /// Tracked rather than re-checking `isRunning` because `start()` is a no-op
  /// that logs on a platform without a PTY: retrying it every rebuild would
  /// fill the scrollback with the same refusal.
  ///
  /// Keyed by pane **identity, not id**. Pane ids are `<chatId>:<n>`, so a
  /// workspace that gets rebuilt produces a *new* pane carrying the *same* id —
  /// and an id-keyed set then reports it as already started, leaving a dead
  /// pane that answers every command with "No shell is running". Identity has
  /// no such collision.
  final _autoStarted = <ShellPane>{};

  /// How much of the assistant's reply has already been mirrored into the
  /// terminal, so a streaming turn appends deltas instead of the whole text.
  String? _mirroredMsgId;
  int _mirroredLen = 0;

  /// Starts [ws]'s focused pane once, after the frame.
  ///
  /// Post-frame because `start()` writes to the scrollback, and mutating what
  /// the console is currently building is a setState-during-build error.
  void _ensureStarted(ShellWorkspace ws) {
    final pane = ws.active;
    if (pane.isRunning || _autoStarted.contains(pane)) return;
    _autoStarted.add(pane);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      pane.start();
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _terminalFocus.addListener(_onTerminalFocusChanged);
  }

  void _onTerminalFocusChanged() {
    if (!mounted || _terminalFocus.hasFocus == _terminalHasFocus) return;
    setState(() => _terminalHasFocus = _terminalFocus.hasFocus);
  }

  @override
  void dispose() {
    _terminalFocus.removeListener(_onTerminalFocusChanged);
    _watchedTerminal?.removeListener(_onTerminalChanged);
    _input.dispose();
    _inputFocus.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  bool _creating = false;

  /// Opens another shell — a second chat tagged `shell`, which the registry
  /// then attaches a workspace to.
  Future<void> _createSession() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final chat = await ref
          .read(chatListProvider.notifier)
          .createChat(section: AppConstants.sectionShell);
      if (!mounted) return;
      context.pushReplacementNamed(
        'shell-session',
        pathParameters: {'id': chat.id},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't start another shell. "
              '${userMessageFor(context, e)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Whether the shell produced output the user has not seen.
  ///
  /// Only meaningful while they are in Ask — in Shell the output is already
  /// on screen, and a second indicator for it would be noise.
  bool _hasUnseenShellOutput(ShellWorkspace ws) {
    if (_mode != ShellInputMode.ask) return false;
    return ws.active.scrollback.revision.value > _shellRevisionOnLeave;
  }

  /// Removes a session, and its work only if that is what was chosen.
  ///
  /// The chat goes either way — it is the conversation the user is done with.
  /// The files are a separate decision, because on a phone this is the only
  /// copy of them.
  Future<void> _deleteSession(ShellWorkspace ws, bool keepFiles) async {
    final registry = ref.read(shellWorkspaceRegistryProvider);
    final leaving = ws.id == widget.chatId;

    await registry?.remove(ws.id, keepFiles: keepFiles);
    await ref.read(chatListProvider.notifier).deleteChat(ws.id);
    if (!mounted) return;

    // Standing in the session that just went is not a place to be.
    if (leaving) {
      context.goNamed('chats');
    } else {
      setState(() {});
    }
  }

  void _submit(ShellWorkspace ws) {
    final text = _input.text.trim();

    final pending = ref.read(pendingAttachmentsProvider(widget.chatId));
    if (_mode != ShellInputMode.run && pending.any((a) => a.uploading)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still uploading…'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // An attachment on its own is a message: "look at this" needs no prose.
    if (text.isEmpty && (_mode == ShellInputMode.run || pending.isEmpty)) {
      return;
    }
    HapticFeedback.lightImpact();
    _input.clear();

    if (_mode == ShellInputMode.run) {
      ws.active.runUserCommand(text);
      // Keep focus — a shell is a sequence of commands, and dropping the
      // keyboard after every one makes it feel like a chat box.
      _inputFocus.requestFocus();
      setState(() {});
      return;
    }

    // The Ask prompt does NOT go into the terminal scrollback.
    //
    // It used to, as a COMMAND line. That scrollback is then sent to the model
    // as "what the human has seen in the pane" — so the model received a
    // terminal transcript whose last line was the user's own request, sitting
    // at a prompt as though it had been typed and run. Asked to `use net_scan
    // on 4.4.4.4`, it read the scrollback, concluded the scan had already
    // happened, and answered "The scan of 4.4.4.4 has been completed
    // successfully" — with no tool call at all.
    //
    // We fed it a transcript of the thing it was being asked to do and it
    // believed it. The message already reaches the model as the message; it
    // does not need to arrive a second time disguised as history.

    // Attachments ride along with the turn, same as in chat. Read and cleared
    // here rather than inside sendMessage so an upload still in flight blocks
    // the send instead of arriving as a half-uploaded reference.
    final attachments =
        ref.read(pendingAttachmentsProvider(widget.chatId).notifier);
    final api = attachments.toApiAttachments();
    attachments.clear();

    ref
        .read(chatDetailProvider(widget.chatId).notifier)
        .sendMessage(text, attachments: api.isEmpty ? null : api);
    _inputFocus.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Put a real Linux under the terminal without asking. Alpine is 4 MB, so
    // "install one to get a package manager" is a prompt nobody needs to read
    // — the app should already be that when they open it. No-ops once any
    // distro is present.
    ref.watch(ensureDefaultDistroProvider);

    // Rehome anything made before sessions had directories of their own, so an
    // upgrade does not leave a user's work outside every session — present on
    // disk and absent from the app, which reads as data loss.
    ref.watch(migrateLegacySessionFilesProvider);

    // Name the session after the conversation, not after a counter. The
    // server derives a title from the first exchange, which is exactly the
    // "what is this session" the ordinal never carried.
    final chatTitle =
        ref.watch(chatDetailProvider(widget.chatId)).valueOrNull?.chat.title;

    final ws = ref.watch(shellWorkspaceProvider(widget.chatId));
    if (ws != null && chatTitle != null) ws.title = chatTitle;

    if (ws == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shell')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    _ensureStarted(ws);
    _watchFullscreen(ws.active.terminal);

    // WATCH, not read. `chatDetailProvider` is autoDispose, and Ask only ever
    // did `ref.read(...notifier).sendMessage(...)` — so the notifier was
    // created, the send started, nothing was listening, and Riverpod tore it
    // down before the stream drained. That is why Ask appeared to do nothing
    // at all: no reply, no tool activity, no error. Watching gives it a
    // listener for as long as the terminal is open.
    ref.watch(chatDetailProvider(widget.chatId));

    // Mirror the assistant's reply INTO the terminal.
    //
    // Without this the answer lands in the chat message list, which this
    // screen does not render — so even a working Ask would look like nothing
    // happened. Deltas are streamed in as they arrive and marked as the
    // agent's, so the shared-scrollback invariant covers the AI half too.
    ref.listen(chatDetailProvider(widget.chatId), (prev, next) {
      final msgs = next.valueOrNull?.messages;
      if (msgs == null || msgs.isEmpty) return;
      final last = msgs.last;
      if (last.role != 'assistant') return;

      if (_mirroredMsgId != last.id) {
        _mirroredMsgId = last.id;
        _mirroredLen = 0;
      }
      if (last.content.length <= _mirroredLen) return;
      final delta = last.content.substring(_mirroredLen);
      _mirroredLen = last.content.length;
      // AskView renders this from chatDetailProvider directly; mirroring it
      // into the grid as well would duplicate the whole reply into the raw
      // session. The transcript still gets it — that is the model's memory.
      ws.active.scrollback.appendStream(delta, source: ShellLineSource.agent);
    });

    final busy = ref.watch(streamRunningProvider);

    final registry = ref.watch(shellWorkspaceRegistryProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      // The sidebar: every open shell, and this shell's panes. Sessions
      // already outlive the screen (the registry holds them above the widget
      // tree) — this is what makes them reachable.
      drawer: registry == null
          ? null
          : ShellSessionsDrawer(
              registry: registry,
              activeId: ws.id,
              onSelectSession: (target) {
                if (target.id == ws.id) return;
                // Replace rather than push: switching shells is lateral
                // movement, and stacking them would make Back walk a history
                // of switches instead of leaving the terminal.
                context.pushReplacementNamed(
                  'shell-session',
                  pathParameters: {'id': target.id},
                );
              },
              onSelectPane: (i) => setState(() => ws.selectPane(i)),
              onNewPane: () => setState(ws.newPane),
              onClosePane: (id) async {
                await ws.closePane(id);
                if (mounted) setState(() {});
              },
              onNewSession: _createSession,
              onDeleteSession: _deleteSession,
            ),
      // Files on the RIGHT, shells on the left. Two panels of the same
      // session: which shell you are in, and what is in it. Splitting them by
      // edge means neither has to be a tab inside the other.
      endDrawer: FileBrowserDrawer(
        session: ws.active.shell,
        onOpenFile: (entry) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FileViewerScreen(
              session: ws.active.shell,
              guestPath: entry.guestPath,
            ),
          ),
        ),
        // Runs a real `cd`, in the user's scrollback, rather than moving the
        // session silently. The terminal is ground truth — a directory change
        // the user cannot see in their history is a directory change they will
        // be surprised by later.
        onChangeDirectory: (guestPath) =>
            ws.active.runUserCommand('cd ${_quote(guestPath)}'),
        // Announced in the scrollback rather than appearing silently. A file
        // materialising in a directory with no explanation reads as a bug, and
        // this is also how the user learns the path to type.
        onImported: (files) {
          for (final f in files) {
            ws.active.recordAgentCommand(
              'imported ${f.name}',
              '${f.guestPath}  (${humanBytes(f.bytes)})',
            );
          }
        },
      ),
      appBar: AppBar(
        // Back stays in the leading slot. Putting the shell switcher there
        // left no way out of the terminal at all — you could reach every
        // shell and never the rest of the app. Back navigation must be
        // predictable and in the place every other screen puts it.
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.popOr('shell'),
        ),
        actions: [
          // Which model is driving Ask. It matters more here than in a chat:
          // tool-calling quality varies sharply between models, and a small
          // one will describe commands instead of running them — so being
          // able to see and change it without leaving the Console is the
          // difference between "the agent is broken" and "wrong model".
          const ModelPickerChip(),
          IconButton(
            tooltip: 'Browser',
            icon: const Icon(Icons.public_rounded),
            // The same browser the agent drives. Reachable from the session
            // rather than from a global menu because signing in is something
            // you do FOR a piece of work, next to that work.
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AgentBrowserScreen(),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Files',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Shells',
              icon: const Icon(Icons.view_sidebar_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ],
        titleSpacing: 0,
        // A gap the actions cannot eat into, so the title never butts up
        // against the model chip.
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ellipsize: a renamed shell can be far longer than the sliver
              // the app bar leaves once the model chip is in the row.
              Text(
                ws.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
              // cwd in the subtitle: in a shell, "where am I" is the single
              // most load-bearing piece of context, and it changes under you
              // when the agent runs `cd`.
              Text(
                _shortCwd(ws.active.shell.cwd, ws.rootDir),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            PaneSwitcher(
              workspace: ws,
              onSelect: (i) => setState(() => ws.selectPane(i)),
              // No explicit start(): the rebuild runs _ensureStarted, which is
              // the same path that starts a pane on reattach. One rule for
              // "a focused pane is a running pane", not two.
              onNew: () => setState(ws.newPane),
              onClose: (id) async {
                await ws.closePane(id);
                if (mounted) setState(() {});
              },
            ),
            Expanded(
              // Two views of ONE session. The terminal is ground truth and
              // keeps running underneath either way; Ask is the readable
              // account of it. IndexedStack rather than a swap so the grid
              // keeps its viewport and PTY attachment — rebuilding
              // TerminalView on every toggle would reset the screen under a
              // running full-screen program.
              child: IndexedStack(
                // MUST be expand. IndexedStack defaults to StackFit.loose, so
                // the terminal sized itself to its content instead of filling
                // — and since it reports its own geometry to the PTY, the
                // shell then wrapped against a grid that did not match the
                // screen. That is the "shell feels broken after switching
                // from Ask" the owner hit.
                sizing: StackFit.expand,
                index: _mode == ShellInputMode.run ? 0 : 1,
                children: [
                  ShellTerminalView(
                    // Keyed by pane so switching panes swaps the grid instead
                    // of animating one terminal into another.
                    key: ValueKey(ws.active.id),
                    terminal: ws.active.terminal,
                    focusNode: _terminalFocus,
                    autofocus: _fullscreen,
                  ),
                  AskView(chatId: widget.chatId),
                ],
              ),
            ),
            // Deliberately its own widget. Reading `viewInsets` here in the
            // SCREEN's build made the whole screen — pane strip, console,
            // input bar — rebuild on every frame of the ~250ms keyboard
            // animation, which is the lag the owner reported. Confining the
            // dependency to this subtree means only the key row rebuilds.
            // What the agent is DOING, live. The owner's report was that Ask
            // showed no running task and no actions — half of that was the
            // provider teardown above, half was that nothing rendered the
            // tool cards in this screen at all.
            // Only in Ask. Agent activity belongs to the agent conversation,
            // not to the screen: a failed `shell_exec` from an earlier turn
            // sitting above the terminal while you type is noise at best, and
            // at worst reads as something wrong with the command you just ran.
            // Switching to Shell is switching to a different thing; the run
            // keeps going and its activity is one tap away in Ask.
            if (!_fullscreen && _mode == ShellInputMode.ask) ...[
              // Ask used to sit completely blank between send and first
              // token — several seconds of a screen that looks broken, which
              // makes people re-send or give up on the feature.
              const AskStatusStrip(),
              AgentActivityStrip(chatId: widget.chatId),
            ],
            _KeyboardKeys(
              // In a full-screen program the row is not a keyboard accessory,
              // it is the ONLY way to send esc and the arrows — neither of
              // which a phone's soft keyboard has, and both of which vi and
              // less are unusable without. So it does not wait for the
              // keyboard to be up.
              // Always in Shell, never in Ask. esc, tab, ctrl and the arrows
              // are not a keyboard accessory here — they send keys a phone
              // keyboard does not have, and Shell has no input box of its own
              // to put them beside.
              always: _fullscreen || _mode == ShellInputMode.run,
              // Keep the key row in full-screen apps — esc and the arrows are
              // exactly what vi and less need, and the soft keyboard has
              // neither.
              // No dismissed state any more: the row cannot be hidden, so it
              // cannot be lost.
              visible: _fullscreen || _mode == ShellInputMode.run,
              row: ExtraKeysRow(
                modifiers: ws.active.modifiers,
                onSend: (data) {
                  // With a live PTY these go straight to the process; until
                  // then they edit the pending command line so the row is
                  // still useful for typing `|`, `~`, `/`, `-`.
                  final pty = ws.active.pty;
                  if (pty != null) {
                    pty.write(data);
                  } else if (data.length == 1 &&
                      !data.codeUnits.any((c) => c < 0x20)) {
                    _input.text += data;
                    _input.selection =
                        TextSelection.collapsed(offset: _input.text.length);
                  }
                },
                // Lowers the keyboard and keeps the row. The keys send
                // characters a phone keyboard does not have, so they are as
                // useful with the keyboard down as up.
                onDismiss: () {
                  _terminalFocus.unfocus();
                  _inputFocus.unfocus();
                  FocusManager.instance.primaryFocus?.unfocus();
                },
              ),
            ),
            if (!_fullscreen)
              // Listening to the scrollback revision, not the whole session:
              // the dot has to appear the moment output arrives while the user
              // is in Ask, and rebuilding only the input bar keeps a chatty
              // command from repainting the transcript above it.
              ValueListenableBuilder<int>(
                valueListenable: ws.active.scrollback.revision,
                builder: (context, _, __) => ShellInputBar(
                  chatId: widget.chatId,
                  controller: _input,
                  focusNode: _inputFocus,
                  mode: _mode,
                  askBusy: busy,
                  shellBusy: _hasUnseenShellOutput(ws),
                  onModeChanged: (m) {
                    // Leaving Shell: remember where the output had got to, so
                    // anything after this counts as unseen. Returning clears it.
                    final rev = ws.active.scrollback.revision.value;

                    // The keyboard carries across the switch unchanged: up
                    // stays up, down stays down. Toggling is a change of what
                    // you are talking to, not of whether you are typing — and
                    // losing the keyboard mid-thought, then having to tap
                    // again, is the kind of friction that makes a phone feel
                    // like the wrong tool.
                    //
                    // Read from the view's real insets, not from focus.
                    // Focus is NOT a proxy for "the keyboard is up": dismissing
                    // it with the back button hides the IME and leaves Flutter
                    // focus intact, so a focus check reports up when the
                    // keyboard is down and then re-opens it on the switch.
                    // Measured on device — this is exactly what happened.
                    //
                    // `View.of` rather than MediaQuery: reading viewInsets
                    // through MediaQuery in this screen registers a dependency
                    // and rebuilds the whole tree on every frame of the
                    // keyboard animation, which is the lag reported earlier.
                    //
                    // Compared against viewPadding, not against zero: under
                    // edge-to-edge the view's bottom inset also carries the
                    // navigation bar, so `> 0` is true even with the keyboard
                    // down — which re-opened it on every switch. The keyboard
                    // is up only when the inset exceeds the system bar it
                    // would otherwise be.
                    final view = View.of(context);
                    final wasUp =
                        view.viewInsets.bottom > view.viewPadding.bottom + 1;

                    setState(() {
                      _mode = m;
                      _shellRevisionOnLeave = rev;
                    });

                    // After the frame, because Ask's field does not exist until
                    // the new mode has been built.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final target = m == ShellInputMode.run
                          ? _terminalFocus
                          : _inputFocus;
                      if (wasUp) {
                        target.requestFocus();
                      } else {
                        // Both, not just the target. After a back-dismiss the
                        // OTHER surface still holds Flutter focus with a live
                        // input connection, so unfocusing only the one we are
                        // switching to is a no-op and the keyboard comes
                        // straight back up. Measured on device.
                        _terminalFocus.unfocus();
                        _inputFocus.unfocus();
                        FocusManager.instance.primaryFocus?.unfocus();
                      }
                    });
                  },
                  onSubmit: () => _submit(ws),
                  onFocus: () {},
                  busy: busy,
                  onStop: () => ref
                      .read(chatDetailProvider(widget.chatId).notifier)
                      .stopStreaming(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// `/data/.../shell/scans` → `~/scans`. Absolute container paths are noise
  /// and eat the whole title bar.
  static String _shortCwd(String cwd, String root) {
    if (cwd == root) return '~';
    if (cwd.startsWith(root)) return '~${cwd.substring(root.length)}';
    return cwd;
  }


  /// Single-quotes a path for the shell.
  ///
  /// Directory names with a space in them are ordinary, and an unquoted `cd`
  /// on one silently changes to the wrong place. Single quotes take everything
  /// literally except a single quote, which is escaped the only way sh allows.
  static String _quote(String path) => "'${path.replaceAll("'", r"'\''")}'";
}

/// Shows [row] only while the soft keyboard is up.
///
/// Exists purely to CONTAIN the `viewInsets` dependency. `viewInsets` changes
/// every frame while the keyboard animates, so anything that reads it rebuilds
/// at 60fps for a quarter of a second — and reading it in the screen's build
/// dragged the console and the pane strip along with it.
class _KeyboardKeys extends StatelessWidget {
  const _KeyboardKeys({
    required this.visible,
    required this.row,
    this.always = false,
  });

  final bool visible;
  final Widget row;

  /// Show regardless of the soft keyboard — see the call site.
  final bool always;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    if (always) return row;
    final up = MediaQuery.viewInsetsOf(context).bottom > 0;
    return up ? row : const SizedBox.shrink();
  }
}
