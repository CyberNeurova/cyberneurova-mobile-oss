import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Page-load telemetry for debug **and profile** builds (no-op in release).
///
/// Profile mode matters more than debug here: debug is JIT with assertions on
/// and is several times slower than what ships, so a debug number tells you
/// almost nothing about real-world feel. Profile is AOT-compiled like release
/// but keeps tracing — it is the build you measure on. This observer used to
/// be `kDebugMode`-only, which meant it went silent in the one mode where its
/// numbers are trustworthy.
///
/// Logs `[route-timing] <route> first frame in <ms>` measured from the
/// navigation event to the end of the first frame that rendered the new
/// route. Watch it while driving the app:
///
///     flutter logs | grep route-timing        # or adb logcat -s flutter
///
/// This is the number the user actually feels as "page load". Screens whose
/// data arrives later (provider fetches) will paint their skeleton within
/// this budget and fill in after — that's by design; a slow FIRST frame here
/// means build-time work that belongs off the hot path.
class RouteTimingObserver extends NavigatorObserver {
  void _stamp(Route<dynamic>? route, String verb) {
    if (kReleaseMode || route == null) return;
    final name = route.settings.name ?? route.settings.runtimeType.toString();
    final sw = Stopwatch()..start();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        '[route-timing] $verb $name — first frame in '
        '${sw.elapsedMilliseconds}ms',
      );
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stamp(route, 'push');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _stamp(newRoute, 'replace');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stamp(previousRoute, 'return-to');
}
