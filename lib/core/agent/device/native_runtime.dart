import 'dart:io';

import 'package:flutter/services.dart';

/// Install-layout facts that only the platform side knows.
///
/// One method matters: [nativeLibraryDir]. See [PrefixBootstrap] for why —
/// it is the only directory an app with a current `targetSdk` may execute a
/// binary from, and Flutter exposes no API for it (`path_provider` gives you
/// the data dirs, all of which SELinux denies execute on).
///
/// Everything here is Android-only and returns null elsewhere rather than
/// throwing: iOS has no equivalent and never will, because AMFI blocks
/// executing any unsigned binary regardless of where it sits.
class NativeRuntime {
  const NativeRuntime._();

  static const MethodChannel _channel =
      MethodChannel('ai.cyberneurova.app/device_runtime');

  /// The app's `nativeLibraryDir`, e.g.
  /// `/data/app/~~<hash>/ai.cyberneurova.app-<hash>/lib/arm64`.
  ///
  /// Null on iOS, and null on Android if the channel isn't wired (an older
  /// install, or a unit test with no platform side). Callers must treat null
  /// as "no bundled toolchain" and carry on with the system binaries — the
  /// shell still works, it just has fewer tools.
  ///
  /// Not cached: the path embeds an install-specific hash, so it changes when
  /// the app updates. It is one binder call at session start.
  static Future<String?> nativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('nativeLibraryDir');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// ABIs this device accepts, most-preferred first. Diagnostics only.
  static Future<List<String>> supportedAbis() async {
    if (!Platform.isAndroid) return const [];
    try {
      final abis = await _channel.invokeListMethod<String>('supportedAbis');
      return abis ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
