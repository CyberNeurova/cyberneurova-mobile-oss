import 'package:flutter/widgets.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';

/// Single entry point for converting an arbitrary error object into a
/// user-facing localized string. Use this everywhere instead of
/// `Text(e.toString())` so users don't see Dio stack traces or internal
/// type-cast errors.
///
/// Falls back gracefully when:
/// - The error is an `AppException` — uses its `.message` (already
///   user-facing) and prefers a localized variant for known codes.
/// - The error is some other object — returns the localized generic
///   "Something went wrong" instead of leaking the raw toString.
/// Whether a server-supplied message is machine noise rather than something
/// a person can act on.
///
/// A denylist, deliberately, not a cleverness test. Most of what the API sends
/// IS written for the user and rewriting it would be worse than leaving it —
/// "8.8.8.8 is outside the authorized scope" says exactly the right thing.
/// What must never reach the screen is the runtime error of whatever the
/// server was talking to when it gave up.
bool isTechnicalErrorMessage(String message) {
  final m = message.trim();
  if (m.isEmpty) return true;
  return _technicalError.hasMatch(m);
}

final RegExp _technicalError = RegExp(
  // Whole-message forms. `fetch failed` is the one that shipped.
  r'^(fetch failed|failed to fetch|network error|load failed|socket hang up'
  r'|request failed|internal server error|bad gateway|null|undefined)\.?$'
  // Anything carrying a runtime/syscall signature, wherever it appears.
  r'|(ECONN[A-Z]*|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|EPIPE|EHOSTUNREACH'
  r'|ERR_[A-Z_]+|undici|SocketException|ClientException|HandshakeException'
  r'|XMLHttpRequest|TypeError|Exception:)'
  // Dart ERRORS, which the list above missed entirely — it covered the
  // Exception family and stopped there.
  //
  // Scope, checked rather than assumed: `userMessageFor` never leaked these,
  // because a non-AppException falls through its type switch to the generic
  // fallback at the bottom. The one path that DID was
  // `installFailureMessage`, which deliberately calls `e.toString()` on
  // whatever it is handed so a good server sentence survives — so a
  // StateError there rendered "Bad state: Bad state: stream already listened
  // to", the prefix doubled because toString() adds its own on top of a
  // message already carrying it. One screen, not the app.
  //
  // Still belongs here rather than at that call site: this is where the
  // knowledge of "what machinery looks like" lives, and the ApiException
  // branch should not echo a Dart-shaped string either if a server ever
  // sends one.
  //
  // Every one of these is a verbatim Dart runtime prefix. None of them is
  // something a server would write to a person, so matching them cannot
  // swallow a real explanation.
  r'|(Bad state:|RangeError|Null check operator|NoSuchMethodError'
  r'|is not a subtype of type|Concurrent modification'
  r'|Invalid argument\(s\)|Unsupported operation:)',
  caseSensitive: false,
);

String userMessageFor(BuildContext context, Object? error) {
  final l = AppL10n.of(context);
  if (error == null) return l.errorGeneric;

  if (error is AppException) {
    switch (error) {
      case NetworkException _:
        return l.errorNetwork;
      case TimeoutException _:
        return l.errorGeneric; // could add a dedicated key later
      case CertificateException _:
        // Clear TLS-failure copy — never show "no internet" for a bad cert.
        return error.message;
      case UnauthorizedException _:
        return l.errorSessionExpired;
      case ForbiddenException _:
        return error.message;
      case NotFoundException _:
      case FeatureUnavailableException _:
        return error.message;
      case QuotaExceededException _:
        return l.errorQuotaExceeded;
      case RateLimitedException r:
        // RateLimitedException carries seconds in its message; if the
        // caller wants the precise placeholder version use l.errorRateLimited
        // directly. Here we use the bare class message.
        return r.message;
      case ServerException _:
      case ServiceUnavailableException _:
        return l.errorServer;
      case ApiException _:
        // The server's message is usually written for a person — "8.8.8.8 is
        // outside the authorized scope" — so it is preferred. But it is not
        // always: a failed image generation came back as the bare string
        // **"fetch failed"**, which is Node's network error surfacing through
        // two hops, and it was rendered to the user under a red icon
        // (device, 2026-08-05). Trust it only when it reads like a sentence.
        return isTechnicalErrorMessage(error.message)
            ? l.errorGeneric
            : error.message;
    }
  }

  // Anything else — typecast errors, raw exceptions from third-party
  // packages — never leak to the user.
  return l.errorGeneric;
}
