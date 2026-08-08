import 'package:flutter/foundation.dart';

/// Dev-only auth + data bypass. `flutter run --dart-define=DEV_AUTH_BYPASS=true`
/// boots the app "logged in" as a fake pro-tier user AND swaps the chat
/// repository for an in-memory mock (canned chats + a fake token stream), so
/// every chat surface — welcome hint, typing indicator, streaming, bubbles,
/// scrolling, Continue pill — is drivable with no account and no network.
///
/// Double-gated: the define does nothing in release builds. See
/// docs/SETUP.md "Dev auth bypass".
const devAuthBypass = kDebugMode && bool.fromEnvironment('DEV_AUTH_BYPASS');

/// Re-runs the bundled-toolchain exec spike at startup.
///
/// Off by default, even in debug. It links nine binaries and SPAWNS PROOT
/// immediately after the first frame — about 600ms of file and process work
/// while the launch animation is still playing, which the owner reported as a
/// visible hang on open. It only ever printed; nothing in the UI reads it, and
/// its answer is already written down in `docs/shell/SPIKE-RESULTS.md`.
///
/// `flutter run --dart-define=PROBE_BUNDLED_TOOLS=true` to measure again after
/// a targetSdk or NDK change, which is the only time the question is open.
const probeBundledTools =
    kDebugMode && bool.fromEnvironment('PROBE_BUNDLED_TOOLS');
