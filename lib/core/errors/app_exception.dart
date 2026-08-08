/// Sealed exception hierarchy. All API errors map to one of these via
/// [ErrorInterceptor]. Display [message] directly to the user — every
/// subclass overrides [toString] to return a clean human-readable message.
sealed class AppException implements Exception {
  const AppException(this.message, {this.code});
  final String message;

  /// Machine-readable code from the backend, e.g. "RATE_LIMITED",
  /// "INVALID_CREDENTIALS", "APPLE_NO_EMAIL". Use for UX branching.
  final String? code;

  @override
  String toString() => message;
}

// ─── Connectivity ────────────────────────────────────────────────────────────

/// No internet / DNS failure / connection refused.
/// Caller should retry once connectivity returns.
final class NetworkException extends AppException {
  const NetworkException([super.message = 'No internet connection.']);
}

/// Request timed out (slow connection or server hang).
final class TimeoutException extends AppException {
  const TimeoutException([
    super.message = 'The request took too long. Try again.',
  ]);
}

/// TLS / certificate validation failed (untrusted cert, MITM proxy, pinning
/// mismatch). Distinct from [NetworkException] so the UI can warn about an
/// insecure connection rather than a generic "no internet", and never retry.
final class CertificateException extends AppException {
  const CertificateException([
    super.message =
        'Secure connection failed: the server certificate could not be verified.',
  ]);
}

// ─── Auth ────────────────────────────────────────────────────────────────────

final class UnauthorizedException extends AppException {
  const UnauthorizedException([
    super.message = 'Session expired. Please log in again.',
    String? code,
  ]) : super(code: code);
}

final class ForbiddenException extends AppException {
  const ForbiddenException([
    super.message = 'You do not have permission to do that.',
    String? code,
  ]) : super(code: code);
}

// ─── Resource state ──────────────────────────────────────────────────────────

final class NotFoundException extends AppException {
  const NotFoundException([super.message = 'Not found.']);
}

/// The feature/endpoint exists in the app but is not deployed/enabled on the
/// backend yet (404 on a known-good path, or explicit 501 Not Implemented).
/// UI should show a friendly "Coming soon" — not an error.
final class FeatureUnavailableException extends AppException {
  const FeatureUnavailableException([
    super.message = 'This feature is not available yet.',
  ]);
}

// ─── Quota / rate limiting ───────────────────────────────────────────────────

/// 402 — token quota exhausted. Show upgrade CTA.
final class QuotaExceededException extends AppException {
  const QuotaExceededException([
    super.message = 'Token quota exceeded. Upgrade or wait for reset.',
  ]);
}

/// 429 — rate limited. Use [retryAfterSeconds] for a user-facing countdown.
final class RateLimitedException extends AppException {
  const RateLimitedException({
    String message = 'Too many requests. Please slow down.',
    String? code,
    this.retryAfterSeconds,
  }) : super(message, code: code);

  final int? retryAfterSeconds;
}

// ─── Server-side failures ────────────────────────────────────────────────────

/// 500-599 generic server error.
final class ServerException extends AppException {
  const ServerException([
    super.message = "Server error. We're on it — try again shortly.",
  ]);
}

/// 503 — service intentionally unavailable (planned maintenance, restart).
final class ServiceUnavailableException extends AppException {
  const ServiceUnavailableException([
    super.message = "We're undergoing maintenance. Back shortly.",
  ]);
}

// ─── Catch-all ───────────────────────────────────────────────────────────────

final class ApiException extends AppException {
  const ApiException(super.message, {this.statusCode, super.code});
  final int? statusCode;
}
