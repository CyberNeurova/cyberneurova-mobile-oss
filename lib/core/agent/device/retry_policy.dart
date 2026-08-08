/// When a failed device tool call is worth running again by itself.
///
/// ## Why this is not a button
///
/// The first cut put a "Run again" on failed cards. That is the agent's job
/// handed to the user: a phone in someone's pocket loses Wi-Fi for a second,
/// a host is asleep, the distro is still extracting — and none of those are
/// things a person should have to notice and tap through. The run should
/// recover and carry on.
///
/// ## Two questions, in order
///
/// **Is repeating this safe?** Asked first, because it is the one that can do
/// harm. A `shell_exec` that failed may have already done half its work —
/// moved a file, started an install, deleted something — and running it again
/// could double-apply it. So retry is limited to calls where repeating cannot
/// make things worse: reads, probes, and a write whose content is fixed by the
/// call itself. Everything else goes back to the model, which can see the
/// error and choose.
///
/// **Could it plausibly succeed next time?** `command not found` will not. A
/// timeout might. Unrecognised failures are NOT retried: the cost of a wrong
/// "no" is one wasted model turn, and the cost of a wrong "yes" is repeating
/// something that should not have been repeated.
library;

/// Tools that may be re-run without a second thought.
///
/// Reads and probes observe; they do not change anything. `file_write` is here
/// because the content comes from the call, so writing it twice leaves exactly
/// the state one successful write would have.
///
/// Deliberately absent: `shell_exec` (arbitrary side effects), `apk_install`
/// (installs software), `file_move` and `file_delete` (destructive, and a
/// half-completed move is exactly the case where repeating is wrong).
const Set<String> kRetryableDeviceTools = {
  'net_discover',
  'net_scan',
  'dns_query',
  'http_probe',
  'mdns_discover',
  'file_read',
  'file_list',
  'file_write',
  'browser_open',
};

/// One attempt, then two retries. Past that it is not a blip.
const int kMaxDeviceAttempts = 3;

/// Failures that can change on their own.
const List<String> _transient = [
  'timed out',
  'timeout',
  'connection refused',
  'connection reset',
  'network is unreachable',
  'no route to host',
  'temporarily unavailable',
  'try again',
  'resource busy',
  'device or resource busy',
  'broken pipe',
  'interrupted system call',
  'socket',
  'i/o error',
  'input/output error',
];

/// Failures that will not, however many times they are tried.
///
/// Checked first: several of these contain words that also appear in
/// transient ones ("host not found" vs "command not found"), and a wrong
/// retry is the more expensive mistake.
const List<String> _permanent = [
  'no tool named',
  'this device cannot run',
  'not authorized',
  'out of scope',
  'outside the authorized scope',
  'permission denied',
  'command not found',
  'not found in path',
  'no such file',
  'no such directory',
  'is a directory',
  'exited 127',
  'cancelled',
];

/// Whether a failed call should be retried automatically.
bool shouldRetryDeviceCall({
  required String tool,
  required String? error,
  required int attempt,
}) {
  if (attempt >= kMaxDeviceAttempts) return false;
  if (!kRetryableDeviceTools.contains(tool)) return false;

  final text = (error ?? '').toLowerCase();
  if (text.isEmpty) return false;

  for (final p in _permanent) {
    if (text.contains(p)) return false;
  }
  for (final t in _transient) {
    if (text.contains(t)) return true;
  }
  // Unrecognised: leave it to the model.
  return false;
}

/// How long to wait before [attempt] (1-based: the wait BEFORE attempt 2).
///
/// Short, because a run is paused meanwhile and a person is watching. Long
/// enough that a Wi-Fi handover or a host waking up has actually had a moment
/// to happen.
Duration deviceRetryBackoff(int attempt) =>
    Duration(milliseconds: attempt <= 1 ? 400 : 1200);
