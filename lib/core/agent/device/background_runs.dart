import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps work alive when the app is not on screen.
///
/// ## The problem
///
/// Everything the device executor does — the PTYs, the agent loop, the
/// downloads — lives in this process. Background an app and Android is free to
/// reclaim it: a build stops halfway, an install stops halfway, and the user
/// finds out only when they come back. On a phone, "come back in a minute" is
/// the normal way to use an app, so this is not an edge case.
///
/// A foreground service is the only supported answer. This class decides when
/// one is needed.
///
/// ## Two costs, counted separately
///
/// **Holding the CPU** (`PARTIAL_WAKE_LOCK`) is what a build or an install
/// needs, and it is the expensive one. Only [_runs] asks for it.
///
/// **Staying resident** is what a live shell or an in-flight answer needs, and
/// it costs approximately nothing: [_sessions] and [_light] ask only for that.
/// An idle prompt does not deserve a wake lock, but it does deserve to still be
/// there when you come back.
///
/// Conflating them is the mistake that turns this into a battery complaint:
/// either idle sessions burn power, or real work gets killed. The owner's rule
/// — "if resources are not being used there is no need to have them running" —
/// is enforced here, in the counting, not in the service.
///
/// ## Balanced by construction
///
/// [beginRun] hands back a token whose `end()` is idempotent. A leaked token is
/// a wake lock held until the platform-side backstop expires, so the API is
/// shaped to make the leak hard: call it in a `finally`, and calling it twice
/// is harmless.
class BackgroundRuns {
  BackgroundRuns._();

  static final BackgroundRuns instance = BackgroundRuns._();

  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('ai.cyberneurova.app/device_runtime');

  int _runs = 0;

  /// Keep-alive tokens: work that must not be killed but does not need the CPU
  /// held — a streaming answer, for instance, where the network does the
  /// waiting and we only need the process to still exist when it arrives.
  int _light = 0;

  int _sessions = 0;
  String? _label;

  /// Last state actually pushed, so an unchanged state costs no binder call.
  ({int runs, int sessions, String? label})? _pushed;

  Timer? _debounce;

  /// Whether anything is currently protected. Exposed for the UI so it can say
  /// so rather than leaving the notification to explain it.
  bool get isProtecting => _runs > 0 || _keepAlive > 0;

  int get runs => _runs;

  /// Clears all state and cancels the pending push. For test isolation only.
  ///
  /// [instance] is a process-wide singleton, and `flutter test` runs every file
  /// in ONE isolate — so its counters and its debounce [Timer] survive from one
  /// test file into the next. Anything in the shell stack that creates a
  /// workspace publishes a session count through here, so a later file inherits
  /// a stale count and a live timer scheduled by an earlier one. That is a
  /// cross-test leak, and it is exactly the kind that turns a suite red only
  /// when files run together (outbox 067). Call this in setUp/tearDown of any
  /// test that touches the stack so neither direction leaks.
  @visibleForTesting
  void resetForTest() {
    _debounce?.cancel();
    _debounce = null;
    _runs = 0;
    _light = 0;
    _sessions = 0;
    _label = null;
    _pushed = null;
    _askedAboutNotifications = false;
  }

  /// Everything that keeps the process alive without holding the CPU.
  int get _keepAlive => _sessions + _light;

  /// Marks the start of real work. Call `end()` on the result when it stops.
  ///
  /// [label] is what the notification says, so it should name the work in the
  /// user's terms — "Installing Kali", not "pty write".
  ///
  /// [holdCpu] is the expensive bit and defaults off. Pass true only when the
  /// work is genuinely running ON this device — a build, an install, an agent
  /// driving a shell. Waiting on the network is not that: the radio wakes us
  /// when the bytes arrive, so holding the CPU through it buys nothing and
  /// costs a measurable amount of battery.
  BackgroundRun beginRun([String? label, bool holdCpu = false]) {
    if (holdCpu) {
      _runs++;
    } else {
      _light++;
    }
    if (label != null) _label = label;
    _schedulePush();
    unawaited(_ensureNotificationsVisible());
    return BackgroundRun._(this, label, holdCpu);
  }

  /// Whether we have already asked about notifications this launch.
  bool _askedAboutNotifications = false;

  /// Makes sure the service's notification can actually be seen.
  ///
  /// The foreground service posts one for exactly this situation — the user
  /// left the app and work is still going — and it carries the only Stop
  /// button that exists outside the app. `POST_NOTIFICATIONS` was declared and
  /// never requested, so on Android 13+ the system dropped it silently:
  /// verified on the handset, a run continuing in the background with
  /// `isForeground=true` and nothing whatsoever in the shade.
  ///
  /// Asked here rather than at launch because this is the first moment it
  /// means anything — the work has just started, so the dialog arrives with a
  /// reason attached. Asked at most once per launch: the system stops showing
  /// it after two refusals, and pestering is how apps teach people to tap Deny.
  Future<void> _ensureNotificationsVisible() async {
    if (_askedAboutNotifications) return;
    _askedAboutNotifications = true;
    try {
      final ok = await channel.invokeMethod<bool>('canPostNotifications');
      if (ok ?? true) return;
      await channel.invokeMethod<bool>('requestNotificationPermission');
    } catch (_) {
      // Best effort. A run must never fail because a permission dialog did.
    }
  }

  void _endRun(String? label, bool heldCpu) {
    if (heldCpu) {
      if (_runs == 0) return;
      _runs--;
    } else {
      if (_light == 0) return;
      _light--;
    }
    if ((_runs == 0 && _light == 0) || _label == label) _label = null;
    _schedulePush();
  }

  /// Reports how many shell sessions are alive. Idempotent — call it whenever
  /// the count changes and let this class work out whether anything moved.
  void setSessions(int count) {
    final next = count < 0 ? 0 : count;
    if (next == _sessions) return;
    _sessions = next;
    _schedulePush();
  }

  /// Coalesces bursts.
  ///
  /// Starting an agent turn that immediately opens a shell would otherwise be
  /// two service starts and two notification posts a few milliseconds apart,
  /// which the user sees as a flicker. One frame of delay removes that without
  /// being perceptible.
  void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), push);
  }

  /// Pushes the current state to the platform side.
  @visibleForTesting
  Future<void> push() async {
    _debounce?.cancel();
    _debounce = null;

    final state = (runs: _runs, sessions: _keepAlive, label: _label);
    if (_pushed == state) return;
    _pushed = state;

    // Android-only by construction: iOS has no foreground services and no
    // wake locks, and there is nothing to keep alive there because it cannot
    // run the tools in the first place.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<bool>('setActiveRuns', {
        'active': _runs,
        'sessions': _keepAlive,
        'text': _label,
      });
    } on PlatformException catch (e) {
      // A service that will not start is a lost guarantee, not a lost run —
      // the work carries on, it just becomes killable. Worth a log and
      // nothing more.
      debugPrint('background service refused: ${e.message}');
    } on MissingPluginException {
      // Tests, or a build without the platform side.
    }
  }

  /// Drops everything. For sign-out and for tests.
  @visibleForTesting
  Future<void> reset() async {
    _runs = 0;
    _light = 0;
    _sessions = 0;
    _label = null;
    await push();
  }
}

/// A single unit of protected work.
class BackgroundRun {
  BackgroundRun._(this._owner, this._label, this._heldCpu);

  final BackgroundRuns _owner;
  final String? _label;
  final bool _heldCpu;
  bool _ended = false;

  /// Safe to call more than once — a double-release must not underflow the
  /// count and strand a wake lock on someone else's run.
  void end() {
    if (_ended) return;
    _ended = true;
    _owner._endRun(_label, _heldCpu);
  }
}
