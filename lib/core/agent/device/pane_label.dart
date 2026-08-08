/// What a pane is actually doing, and what to call it.
///
/// ## Why `pane 1 / pane 2 / pane 3` had to go
///
/// A pane switcher that names panes by ordinal is unreadable the moment there
/// are three of them: the labels carry no information the position doesn't
/// already give you. tmux solved this decades ago by naming a pane after the
/// program running in it — `vim`, `htop`, `python` — and falling back to the
/// shell when nothing is running. `docs/shell/09-T3CODE-TEARDOWN.md` §4 flags
/// the same gap against T3's implementation.
///
/// On Android that information is free: the shell's children are visible in
/// `/proc`, and since Android 9 mounts it with `hidepid`, an app sees its own
/// processes and nobody else's — which is exactly the set we want. No
/// permission, no root.
///
/// ## And why a bool was not enough for status
///
/// `isRunning` collapses three different situations into `false`: never
/// started, exited cleanly, and died with an error. A session list rendering
/// from that cannot be honest — "stopped" over a pane whose build just failed
/// is the same invisible-failure trap as a swallowed command.
library;

/// A pane's lifecycle, distinguishable enough to render truthfully.
enum PaneStatus {
  /// Created but never started. The registry builds a pane before any screen
  /// asks for one, so this is the normal state of a pane nobody has opened.
  idle,

  running,

  /// The shell ended on its own — the user typed `exit`, usually.
  exited,

  /// The shell ended badly, or never started. Worth showing differently:
  /// this is the state that means something is wrong.
  failed,
}

extension PaneStatusDisplay on PaneStatus {
  String get description => switch (this) {
        PaneStatus.idle => 'not started',
        PaneStatus.running => 'running',
        PaneStatus.exited => 'exited',
        PaneStatus.failed => 'failed',
      };
}

/// Parent pid from the contents of `/proc/<pid>/stat`.
///
/// Split from the last `)` rather than on whitespace: the second field is the
/// executable name in parentheses and it can contain both spaces and
/// parentheses. A process helpfully named `sh (2)` breaks every naive split,
/// and it breaks it by returning a *plausible wrong number*, which is worse
/// than returning nothing.
int? ppidFromStat(String stat) {
  final close = stat.lastIndexOf(')');
  if (close < 0) return null;
  final rest = stat.substring(close + 1).trim().split(RegExp(r'\s+'));
  // rest[0] is state, rest[1] is ppid.
  if (rest.length < 2) return null;
  return int.tryParse(rest[1]);
}

/// The command a pane should be named after, or null to fall back to the shell.
///
/// [chain] is the process names from the shell downwards, as read from `comm`.
/// The deepest one wins — running `git log` opens a pager, and `less` is what
/// the user is actually looking at.
///
/// Shell names are skipped so a shell that spawned a subshell is still "idle"
/// rather than being labelled `sh` in a way that looks like activity.
String? foregroundFromChain(List<String> chain) {
  for (final name in chain.reversed) {
    final c = name.trim();
    if (c.isEmpty) continue;
    if (_shellNames.contains(c)) continue;
    return c;
  }
  return null;
}

const _shellNames = {'sh', 'bash', 'zsh', 'dash', 'ash', 'busybox', 'proot'};

/// The label to show for a pane.
///
/// Precedence, and each step is a deliberate answer to "who decides the name":
///  1. a name the user typed — never overridden, or renaming would not stick
///  2. the foreground program — the tmux behaviour, and the useful one
///  3. the shell's own name — honest when the pane is just sitting at a prompt
String paneLabel({
  String? userTitle,
  String? foreground,
  required String shellName,
  required PaneStatus status,
}) {
  if (userTitle != null && userTitle.trim().isNotEmpty) return userTitle.trim();
  if (status == PaneStatus.running && foreground != null) return foreground;
  return shellName;
}
