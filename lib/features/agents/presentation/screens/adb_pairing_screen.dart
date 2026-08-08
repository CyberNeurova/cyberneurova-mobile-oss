import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cyberneurova_mobile/core/agent/device/linux/shell_service.dart';
import 'package:cyberneurova_mobile/core/routing/safe_pop.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/shared/theme/app_theme.dart';
import 'package:cyberneurova_mobile/core/agent/device/linux/paired_devices.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/paired_history.dart';

/// Pairing the phone with its own wireless debugging.
///
/// The user has to read a six-digit code out of Settings, so the screen is
/// built around that reality rather than pretending it can be automated: take
/// them to the right screen, tell them exactly which number to copy, and be
/// specific when it fails.
///
/// The one thing this screen must get right is **which port**. Android shows
/// two, seconds apart, and they are not interchangeable — the pairing dialog's
/// port is the one we need, not the one on the page behind it. Every report of
/// "pairing just fails" traces back to that.
class AdbPairingScreen extends ConsumerStatefulWidget {
  const AdbPairingScreen({super.key});

  @override
  ConsumerState<AdbPairingScreen> createState() => _AdbPairingScreenState();
}

class _AdbPairingScreenState extends ConsumerState<AdbPairingScreen> {
  final _portController = TextEditingController();
  final _codeController = TextEditingController();
  final _scroll = ScrollController();

  bool _busy = false;
  String? _error;
  String? _success;

  bool _paired = false;
  bool _connected = false;

  /// Set when a Connect is refused despite [_paired] — the key on disk exists
  /// but the device no longer trusts it (revoke debugging authorisations, or a
  /// reset). It is a THIRD state, not a shade of "paired": Connect will keep
  /// failing until the user pairs AGAIN, so the screen must stop leading with
  /// Connect and lead with re-pairing instead. `isPaired()` cannot tell us this
  /// — it only checks the key file exists — so it is learned from a refused
  /// connect and cleared the moment one succeeds.
  bool _keyRefused = false;

  List<PairedDevice> _history = const [];
  String? _device;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  /// Pairing and connection are separate facts, so ask for both.
  ///
  /// The connection query also returns which device and at what uid, because
  /// "connected" on its own is not reassuring for something that can install
  /// apps without asking.
  Future<void> _refreshState() async {
    final paired = await AdbPairing.isPaired();
    final info = await AdbPairing.connectionInfo();

    // Recorded on CONNECT, not on pair: pairing can succeed and connecting
    // still fail, and a list of grants that never worked would be noise.
    if (info.connected) {
      await PairedDevices.remember(
        id: info.device ?? 'this-device',
        name: info.device ?? 'This device',
        uid: info.uid,
      );
    }
    final history = await PairedDevices.all();

    if (!mounted) return;
    setState(() {
      _paired = paired;
      _connected = info.connected;
      // A live connection means the key is trusted; drop any stale
      // refused-key state so the screen stops offering to re-pair.
      if (info.connected) _keyRefused = false;
      _device = info.device;
      _uid = info.uid;
      _history = history;
    });
  }

  Future<void> _disconnect() async {
    await AdbPairing.disconnect();
    await _refreshState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        // Says what it did NOT do, because "disconnected" invites the belief
        // that the grant is gone. The key on disk survives, which is exactly
        // why reconnecting later needs no code.
        content: Text('Disconnected. The pairing is kept, so reconnecting '
            'needs no code.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    _codeController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Shows the outcome of an action, and makes sure it is on screen.
  ///
  /// The message used to render at the very END of this list — below the three
  /// setup steps, the notification button, both code fields and a second
  /// Connect. Tapping Connect at the TOP therefore produced a failure notice
  /// roughly a thousand pixels below the fold. Wireless debugging is off after
  /// every reboot, so that tap fails routinely, and the screen answered it
  /// with a blank stare. Reported as "I'm trying to click connect on android
  /// but nothing happens" — which is precisely what it looked like.
  ///
  /// The note now sits under the status strip and the list scrolls up to it,
  /// so the outcome and the state it changed are read together, whichever
  /// button produced it.
  void _report({String? error, String? success}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _success = success;
    });
    if (error == null && success == null) return;
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    final typedPort = int.tryParse(_portController.text.trim());

    if (code.length != 6 || int.tryParse(code) == null) {
      _report(error: 'The pairing code is six digits.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    // Find the port rather than make the user copy it. It changes every time
    // the dialog reopens, so it is the half most likely to be stale by the
    // time anyone finishes typing. A typed port still wins if given.
    var port = typedPort;
    if (port == null || port <= 0) {
      final found = await AdbPairing.discoverPairingPort();
      if (!mounted) return;
      if (!found.ok) {
        _report(
          error: found.error ??
              'Could not find an open pairing dialog on this device.',
        );
        return;
      }
      port = found.port;
    }

    final paired = await AdbPairing.pair(port: port, code: code);
    if (!mounted) return;

    if (!paired.ok) {
      // Codes expire quickly and the dialog regenerates one each time it
      // opens, which is the likeliest cause and not obvious.
      _report(
        error: '${paired.error ?? 'Pairing failed.'}\n\n'
            'Pairing codes expire. Close the dialog, open it again for a '
            'fresh code and port, and retry.',
      );
      return;
    }

    // Pairing alone does nothing useful — connect immediately so the user
    // sees a working state rather than "paired" and a shrug.
    final connected = await AdbPairing.connect();
    if (!mounted) return;

    // Pairing succeeded, so whatever key was refused is trusted again — clear
    // the re-pair state whether or not the follow-up connect lands.
    _keyRefused = false;
    if (connected.ok) {
      _report(success: 'Paired and connected.');
    } else {
      _report(
        error: 'Paired, but could not connect: '
            '${connected.error ?? 'unknown'}. Keep wireless debugging on and '
            'tap Connect.',
      );
    }
    ref.invalidate(shellServiceStatusProvider);
    _refreshState();
  }

  /// Posts the notification prompt and sends the user to Settings.
  ///
  /// Both in one tap because they are one action: the prompt is useless
  /// without the dialog, and the dialog is useless without somewhere to type.
  Future<void> _startNotificationFlow() async {
    final posted = await ShellService.showPairingNotification();
    if (!mounted) return;
    if (!posted) {
      _report(
        error: 'Could not post the notification. Allow notifications for '
            'this app, or use the fields below instead.',
      );
      return;
    }
    _report(
      success: 'Prompt posted. Open the pairing dialog, then pull down the '
          'notification shade and type the code there — do not come back to '
          'this screen, that closes the dialog.',
    );
    await ShellService.openWirelessDebuggingSettings();
  }

  void _openSettings() {
    ShellService.openWirelessDebuggingSettings();
  }

  /// The message for a connect that failed with the toggle off.
  ///
  /// Named because it is the answer roughly every time: Android clears
  /// wireless debugging on reboot, and nothing about the failure says so on
  /// its own. "Could not reach wireless debugging" describes the symptom to
  /// someone who wanted to be told what to do about it.
  static const _debuggingIsOff =
      'Wireless debugging is switched off, so there is nothing to connect '
      'to. Android turns it off every time the phone reboots. Open Developer '
      'options -> Wireless debugging, turn it on, then tap Connect — no code '
      'needed.';

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    // Ask before browsing. Discovery takes ten seconds to fail and cannot
    // tell "the toggle is off" from "the network is slow"; the setting
    // answers instantly and exactly.
    if (await AdbPairing.isWirelessDebuggingOn() == false) {
      _report(error: _debuggingIsOff);
      return;
    }

    final r = await AdbPairing.connect();
    if (!mounted) return;
    if (r.ok) {
      // A live connection proves the key is trusted again, whatever state we
      // thought we were in.
      _keyRefused = false;
      // The status strip names the device and the uid, so saying it again
      // here would be a second place to keep true.
      _report();
      ref.invalidate(shellServiceStatusProvider);
      await _refreshState();
      return;
    }

    if (r.needsPairing) {
      // Two different facts, and they disagree more often than you would
      // think. `_paired` means WE hold a key; needsPairing means adbd refused
      // it. Saying "not paired yet" under a strip reading "Paired with this
      // device — key stored" is a screen arguing with itself, and it leaves
      // the reader with no idea which half to believe or what to do.
      //
      // When we DO hold a key and it was refused, this is the revoked-key
      // state: latch it so the screen leads with re-pairing instead of a
      // Connect button that will fail the same way every time.
      _keyRefused = _paired;
      _report(
        error: _paired
            ? 'The stored key was refused, so it no longer matches this '
                'device — revoking debugging authorisations or a reset will '
                'do that. Pair again below for a fresh one.'
            : 'This device has not been paired yet. Do that first.',
      );
    } else if (await AdbPairing.isWirelessDebuggingOn() == false) {
      // It was on when we started and is off now, or the first read came back
      // null on a ROM that only answers sometimes. Either way this is the
      // useful sentence.
      _report(error: _debuggingIsOff);
    } else {
      _report(
        error: '${r.error ?? 'Could not connect.'} Check that Developer '
            'options -> Wireless debugging is on and this phone is on Wi-Fi.',
      );
    }
    ref.invalidate(shellServiceStatusProvider);
    _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.popOr('agent-environment'),
        ),
        title: const Text('Pair with this device'),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StatusStrip(
            paired: _paired,
            connected: _connected,
            device: _device,
            uid: _uid,
          ),
          // Directly under the strip, because every message on this screen is
          // about the state the strip is showing. See [_report] for why it is
          // not at the bottom any more.
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Note(text: _error!, color: cs.error),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            _Note(text: _success!, color: cs.primary),
          ],
          if (_connected) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 17),
                label: const Text('Disconnect'),
              ),
            ),
          ],
          // Already paired: Connect is the only thing left to do, so it is the
          // only thing offered up here.
          //
          // The screen used to show the same content in every state — three
          // first-time setup steps, "Pair from the notification" as the green
          // primary, two code fields and a second Pair button, with Connect a
          // quiet outline below all of it. On a device that was already paired
          // every one of those was noise in front of the one useful control.
          // The page even ended by saying "the pairing is remembered, so you
          // only need Connect again" while burying Connect.
          //
          // NOT when the key was refused (`_keyRefused`): Connect will fail the
          // same way every time until the user pairs again, so leading with it
          // is the trap that made "I kept failing to connect a new key". In
          // that state the block below is suppressed and the pair-again flow
          // becomes the first thing under the explanation.
          if (_keyRefused) ...[
            const SizedBox(height: 14),
            Text(
              'Pair again to fix this',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The device dropped its trust in this app, so there is nothing to '
              'reconnect to — you have to pair once more. It is the same short '
              'flow as the first time, and it reuses the key already on the '
              'phone, so nothing here is lost. Use "Pair from the notification" '
              'below; it is the one path that does not close the pairing dialog '
              'out from under you.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
            ),
          ],
          if (_paired && !_connected && !_keyRefused) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
            const SizedBox(height: 6),
            Text(
              'This device is already paired. Wireless debugging switches '
              'itself off when you reboot, so turn it back on in Developer '
              'options and tap Connect — no code needed.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openSettings,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open Developer options'),
            ),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 8),
            PairedHistory(
              devices: _history,
              onForget: (id) async {
                await PairedDevices.forget(id);
                await _refreshState();
              },
            ),
          ],
          const SizedBox(height: 16),
          if (ref.watch(rootGrantProvider).isUsable) ...[
            _Note(
              text: 'This device has root, so you do not need any of this. '
                  'Root already covers everything pairing would give you, and '
                  'raw sockets besides — which shell access cannot do at all.',
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Your phone pairs with itself over its own wireless debugging. '
            'Nothing leaves the device, and you do not need a computer or '
            'root.',
            style: TextStyle(
                fontSize: 13, height: 1.45, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          const _Step(
            n: 1,
            text: 'In Developer options, turn Wireless debugging ON — then '
                'tap the words "Wireless debugging" to open its own screen. '
                'The switch turns it on; tapping the label opens it. They are '
                'two separate taps, and the pairing option only lives on that '
                'inner screen — not in the main list.',
          ),
          const _Step(
            n: 2,
            text: 'On that screen, tap "Pair device with pairing code". Leave '
                'the dialog it opens on screen.',
          ),
          const _Step(
            n: 3,
            text: 'Pull down the notification shade and type the six digits '
                'there. Do NOT come back to this screen — that closes the '
                'dialog and the code stops working.',
            highlight: true,
          ),
          const SizedBox(height: 14),
          // The path that actually works on every device. Everything below is
          // the fallback for when the notification is unavailable.
          FilledButton.icon(
            onPressed: _busy ? null : _startNotificationFlow,
            icon: const Icon(Icons.notifications_active_rounded, size: 18),
            label: const Text('Pair from the notification'),
          ),
          const SizedBox(height: 6),
          Text(
            'Puts a prompt in your notification shade. Open the pairing '
            'dialog, pull the shade down without leaving it, and type the six '
            'digits there. The dialog stays open, so the code stays valid.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openSettings,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open Developer options'),
          ),
          const SizedBox(height: 22),
          // Stacked, not side by side: on a 360dp screen two Expanded fields
          // with labels and helper text leave neither readable.
          TextField(
            controller: _portController,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTheme.mono(fontSize: 15, color: cs.onSurface),
            decoration: const InputDecoration(
              labelText: 'Pairing port (optional)',
              hintText: 'found automatically',
              helperText: 'Leave blank unless discovery fails',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTheme.mono(fontSize: 15, color: cs.onSurface),
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              hintText: '201062',
              counterText: '',
              helperText: 'Six digits',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pair'),
          ),
          const SizedBox(height: 10),
          // Separate from Pair: once paired the device remembers us, and only
          // the connection needs re-establishing after a reboot.
          OutlinedButton(
            onPressed: _busy ? null : _connect,
            child: const Text('Connect'),
          ),
          const SizedBox(height: 26),
          Text(
            'What this unlocks',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Installing and removing apps without a prompt each time, the '
            'full list of installed packages, and granting the app '
            'permissions it would otherwise have to ask for.\n\n'
            'It is not root: packet capture, SYN scans and monitor mode need '
            'more than this and are unaffected.\n\n'
            'Wireless debugging switches itself off when you reboot. The '
            'pairing is remembered, so you only need Connect again.',
            style: TextStyle(
                fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text, this.highlight = false});

  final int n;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlight
                  ? cs.primary.withValues(alpha: 0.18)
                  : cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: highlight ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: highlight ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, height: 1.4, color: color),
      ),
    );
  }
}

/// Pairing and connection, shown separately.
///
/// They are different facts with different lifetimes and users conflate them:
/// the pairing is a key on disk that survives reboots, the connection is a
/// socket that does not. Showing one number for both is how "I have to pair
/// again every time" gets believed.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.paired,
    required this.connected,
    this.device,
    this.uid,
  });

  final bool paired;
  final bool connected;
  final String? device;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          _row(cs, 'Paired with this device', paired,
              paired ? 'Key stored — no code needed again' : 'Not yet'),
          const SizedBox(height: 8),
          _row(
            cs,
            connected && device != null
                ? 'Connected to $device'
                : 'Connected now',
            connected,
            switch ((connected, uid)) {
              (false, _) => 'Tap Connect',
              (true, '0') => 'uid 0 — a root service. Everything is available.',
              (true, '2000') => 'uid 2000 · silent install and uninstall, full '
                  'package list. Raw sockets still need root.',
              // Any other uid is unexpected; show it rather than describe
              // capabilities we have not confirmed.
              (true, final u?) => 'uid $u',
              (true, null) => 'Connected, privilege not yet checked',
            },
          ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, String label, bool ok, String detail) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 18,
          color: ok ? cs.primary : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Text(
                detail,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

