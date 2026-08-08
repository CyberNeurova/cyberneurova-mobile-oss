/// Spotting a request that needs the device, in a chat that cannot reach it.
///
/// ## The failure this exists to stop
///
/// The owner's report, verbatim: *"i told it to write something ... it says it
/// did but when i go to the shell and ls nothing is there."* That was an
/// ordinary chat. Ordinary chats have no device tools by design, and the model
/// is never told so — the `deviceContext` block that would say it is dropped
/// server-side for any section other than `shell`. So it answers as though it
/// had done the work, and from the user's side an imagined action and a refused
/// one look identical.
///
/// Since the model cannot be corrected from here, the request has to be caught
/// before it is sent. One tap moves it to a surface that can actually do it,
/// and the wasted turn never happens.
///
/// ## Deliberately conservative
///
/// A false positive costs a dismissible suggestion; a false negative costs the
/// exact confusion above. That asymmetry argues for a wide net — but a chip
/// that appears on every third message is one people learn to ignore, which
/// costs the true positives too. So: match on phrases that are hard to say by
/// accident, and require the imperative or possessive framing that separates
/// "run this on my phone" from "how do I run this".
library;

/// Whether [message] reads as asking for work on the user's own device.
bool looksLikeDeviceRequest(String message) {
  final text = message.toLowerCase().trim();
  if (text.length < 6) return false;

  // Naming THIS device wins outright, question or not. "What is running on
  // this phone" opens like a question and still cannot be answered without
  // the device — vetoing it on the opener alone was the one case that got
  // this wrong.
  for (final phrase in _strongPhrases) {
    if (text.contains(phrase)) return true;
  }

  // Asking HOW is a question for a chat; asking to DO it is a job for the
  // Console. Applied only to the verb rule below, which is the loose one:
  // "how do i install docker" must not fire on `install`.
  for (final q in _questionOpeners) {
    if (text.startsWith(q)) return false;
  }

  // A shell verb at the very start reads as an instruction: "install ripgrep",
  // "clone the repo". Mid-sentence the same word is usually discussion.
  for (final verb in _leadingVerbs) {
    if (text == verb || text.startsWith('$verb ')) return true;
  }

  return false;
}

/// Openers that make the whole message a question about doing something,
/// rather than an instruction to do it.
const _questionOpeners = [
  'how do i',
  'how can i',
  'how would i',
  'how does',
  'what is',
  "what's",
  'what does',
  'why does',
  'why is',
  'can you explain',
  'explain',
  'what are',
  'is there a way',
];

/// Phrases that are hard to say unless you mean the device in front of you.
const _strongPhrases = [
  'on my phone',
  'on this phone',
  'on my device',
  'on this device',
  'in my terminal',
  'my terminal',
  'in the shell',
  'in my shell',
  'my working directory',
  'the current directory',
  'my files',
  'this directory',
  'run it locally',
  'run this locally',
  'on my network',
  'my local network',
  'scan my',
];

/// Verbs that, at the start of a message, are an instruction to act.
const _leadingVerbs = [
  'run',
  'execute',
  'install',
  'uninstall',
  'clone',
  'compile',
  'build',
  'chmod',
  'mkdir',
  'touch',
  'ls',
  'cd',
  'cat',
  'grep',
  'apt',
  'apk',
  'pip',
  'npm',
  'git clone',
  'nmap',
  'curl',
  'wget',
];
