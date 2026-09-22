import 'package:flutter/material.dart';

import 'package:cyberneurova_mobile/core/constants/app_constants.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';

/// What one agent surface is for, in the model's words and the user's.
///
/// ## Why the surfaces need to differ at all
///
/// All three agent surfaces carry the same device tools — that was the owner's
/// call, and it is right: the point of the agent surfaces is that work happens
/// on the user's phone, so Code can build an app here and Research can use this
/// network rather than ours.
///
/// But identical tools do not mean identical jobs. Given only a tool list, a
/// Research session will happily start rewriting files, and a Console session
/// will write an essay when the user wanted a command. The tools say what is
/// *possible*; nothing said what each surface is *for*, so the model guessed,
/// and it guessed differently every session.
///
/// ## And why the user needs it too
///
/// The same gap shows up on the other side. Someone opening Research has no way
/// to know it can reach their LAN; someone in a plain chat has no way to know it
/// cannot touch anything — which is exactly the confusion behind "it said it
/// wrote the code but the shell is empty". One description, rendered for the
/// model and shown to the user, keeps those two answers from drifting apart.
enum AgentSurface {
  /// Terminal and agent sharing one session, one directory, one scrollback.
  console(
    section: AppConstants.sectionShell,
    title: 'Console',
    summary: 'A real terminal you can also talk to. You and the agent share '
        'one session, directory and scrollback.',
    userCapabilities: [
      'Runs commands on this phone, in your shell',
      'Reads and writes files in your session directory',
      'Scans and probes the networks you authorise',
      'Everything it runs appears in your scrollback',
    ],
    icon: Icons.terminal_rounded,
    starters: [
      'What is running on this phone right now?',
      'Install ripgrep and show me it works',
      'Find every large file in my session directory',
    ],
    focus: 'You are in the Console: a terminal the user is watching. They can '
        'see every command you run, in the same scrollback, marked as yours. '
        'Prefer running the command over describing it. Keep prose short — '
        'the output is the answer. When something fails, read the actual '
        'error before proposing a fix.',
  ),

  /// A codebase on the phone, worked across files.
  code(
    section: AppConstants.sectionCode,
    title: 'Code',
    summary: 'Build and iterate on a codebase across files, with your project '
        'on hand between turns.',
    userCapabilities: [
      'Creates and edits real files on this phone',
      'Runs builds, tests and servers in your shell',
      'Installs the toolchains a project needs',
      // NOT "keeps the whole project in view": the conversation carried
      // between turns is six turns, truncated to 600 characters each, with
      // tool results excluded (`_withPriorTurns`) — agent turns are not stored
      // server-side at all (outbox 054). What genuinely persists is the files,
      // which the agent can re-read whenever it needs them. Promising context
      // it does not have is how a user ends up wondering why it forgot.
      'Your files stay on the phone — it can re-read them any turn',
    ],
    icon: Icons.code_rounded,
    starters: [
      'Build me a snake game I can play here',
      'Start a small web page and show me a preview',
      'Set up a Python project with a test that passes',
    ],
    focus: 'You are in Code: the user is building something on this phone, '
        'and for many of them it is the only computer they have. Write real '
        'files with the file tools — do NOT print a code block and call it '
        'done, because nothing you only describe will exist afterwards. Run '
        'the thing you wrote and report what actually happened. Keep changes '
        'small enough to verify on a phone screen. '
        // Measured on device: asked to create and run hello.py, the agent
        // wrote the file correctly and then spent fifteen tool calls hunting
        // for a python binary that was never in the image, before giving up.
        // `apk` was sitting in /sbin the whole time. It does not need
        // permission to install a runtime — that is what "installs the
        // toolchains a project needs" promises the user.
        'If a language or tool is missing, INSTALL IT and carry on: '
        'Alpine uses `apk add <pkg>` (python3, nodejs, go, rust), Debian, '
        'Ubuntu and Kali use `apt-get install -y <pkg>`. Do not spend turns '
        'searching the filesystem for something you can install in one '
        'command, and do not report a missing interpreter as a dead end.',
  ),

  /// Investigation, from the user's own network.
  research(
    section: AppConstants.sectionResearch,
    title: 'Research',
    summary: 'Multi-source investigation with cited sources, grouped into '
        'sessions by topic.',
    userCapabilities: [
      'Searches and fetches from your own connection',
      'Probes hosts and networks you authorise',
      'Saves findings as files you keep',
      'Cites what it actually read, not what it recalls',
    ],
    icon: Icons.science_rounded,
    starters: [
      'What is on my network right now?',
      'Look up the latest CVEs for the software I am running',
      'Investigate this and save the findings to a file',
    ],
    focus: 'You are in Research: the user wants findings they can check, not '
        'a confident summary. Requests leave from THEIR connection and their '
        'IP, so treat scope as a real limit rather than a formality. Cite '
        'what you actually fetched. Write findings to files so they survive '
        'the session. Do not reorganise the filesystem — you are here to '
        'investigate, not to tidy.',
  );

  const AgentSurface({
    required this.section,
    required this.title,
    required this.summary,
    required this.userCapabilities,
    required this.focus,
    required this.icon,
    required this.starters,
  });

  /// The chat `section` tag this surface owns.
  final String section;

  final String title;

  /// One sentence, for the surface's card.
  final String summary;

  /// What it can do, in the user's terms. Deliberately about outcomes rather
  /// than tool names — "runs commands on this phone" is checkable by someone
  /// who has never heard of a PTY.
  final List<String> userCapabilities;

  /// Shown wherever the surface introduces itself.
  final IconData icon;

  /// First things to try, in the surface's own terms.
  ///
  /// The generic chat starters ("Brainstorm ideas", "Explain a concept") point
  /// AWAY from a surface someone deliberately chose. These point further in.
  final List<String> starters;

  /// The `SURFACE:` block sent to the model.
  ///
  /// Says what the surface is FOR. The capability block that follows it says
  /// what the device can DO, and the two are kept apart on purpose: the device
  /// facts change between turns, this does not.
  final String focus;

  /// How many tool-and-reply rounds this surface is allowed before the server
  /// stops the run (`/agent/run` `maxTurns`, clamped to 50 server-side).
  ///
  /// Per-surface because the jobs are not the same shape, which is what
  /// outbox 054 was about — Code was hitting the ceiling mid-build:
  ///
  ///  * **Code** gets the most. Installing a toolchain, writing files, running
  ///    the thing and fixing what broke is genuinely many rounds, and stopping
  ///    halfway leaves a half-built project the user has to finish by hand.
  ///  * **Research** sits between. Fetch, read, follow a link, write findings.
  ///  * **Console** gets the fewest, and that is not a limitation: the user is
  ///    watching a terminal and can steer after any answer. A long unattended
  ///    chain there is a runaway, not thoroughness.
  int get maxTurns => switch (this) {
        AgentSurface.code => 40,
        AgentSurface.research => 30,
        AgentSurface.console => 20,
      };

  /// Whether this surface needs a real shell on the device to mean anything.
  ///
  /// Console and Code both promise it in their own words above — "runs
  /// commands on this phone, in your shell", "creates and edits real files on
  /// this phone". On a platform that cannot provide one those are not degraded
  /// features, they are untrue sentences, and the honest thing is not to offer
  /// the surface. Research asks the same device for its network but reads its
  /// sources over HTTP, so it stands on its own anywhere.
  bool get needsDeviceShell => this != AgentSurface.research;

  /// Whether this surface can do what it says on the machine it is running on.
  bool get isAvailableHere =>
      !needsDeviceShell || PlatformFlags.hasDeviceShell;

  /// The surface owning [section], or null for a plain chat.
  ///
  /// Null is meaningful: it is how the rest of the app knows a session has no
  /// device tools at all.
  static AgentSurface? forSection(String? section) {
    for (final s in AgentSurface.values) {
      if (s.section == section) return s;
    }
    return null;
  }

  /// The block that goes above the device capabilities in the prompt.
  String get promptBlock => 'SURFACE: $title\n$focus';
}
