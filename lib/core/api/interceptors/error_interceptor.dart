import 'package:dio/dio.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';

/// Maps raw [DioException] errors to typed [AppException] subclasses,
/// extracting the backend's standard error envelope:
///
///     { "error": "...", "code": "...", "retryAfter": 60, "details": {...} }
///
/// All connectivity failures (no response, timeouts, DNS errors) become
/// [NetworkException] or [TimeoutException] so the UI can show the right state.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // ── Connectivity-level failures (no HTTP response from server) ───────────
    switch (err.type) {
      case DioExceptionType.connectionError:
        return handler.reject(
          err.copyWith(error: const NetworkException()),
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return handler.reject(
          err.copyWith(error: const TimeoutException()),
        );
      case DioExceptionType.cancel:
        // Caller cancelled — propagate as-is, don't wrap as an error.
        return handler.next(err);
      case DioExceptionType.badCertificate:
        // TLS validation failed — surface a distinct, non-retryable secure-
        // connection error rather than a generic "no internet".
        return handler.reject(
          err.copyWith(error: const CertificateException()),
        );
      case DioExceptionType.unknown:
        // unknown often means network/DNS issue → treat as network
        if (err.response == null) {
          return handler.reject(
            err.copyWith(error: const NetworkException()),
          );
        }
        break;
      case DioExceptionType.badResponse:
        break; // handled below
    }

    // ── HTTP response from server — map status + envelope ────────────────────
    final response = err.response;
    final status = response?.statusCode;
    final envelope = _envelope(response);
    final message = envelope.message;
    final code = envelope.code;

    // Detect "endpoint not deployed yet" vs "resource truly missing".
    // 404 with Content-Type: text/html (a Next.js 404 page) or with no JSON
    // envelope means the route doesn't exist — treat as feature unavailable.
    // 404 with a proper JSON envelope means the resource is missing.
    if (status == 404) {
      final isJsonResponse = response?.headers
              .value('content-type')
              ?.toLowerCase()
              .contains('application/json') ??
          false;
      if (!isJsonResponse) {
        return handler.reject(
          err.copyWith(error: const FeatureUnavailableException()),
        );
      }
    }

    final mapped = switch (status) {
      400 => ApiException(
          message ?? 'Invalid request.',
          statusCode: 400,
          code: code,
        ),
      401 => UnauthorizedException(message ?? 'Session expired.', code),
      402 => QuotaExceededException(message ?? 'Quota exceeded.'),
      403 => ForbiddenException(message ?? 'Access denied.', code),
      404 => NotFoundException(message ?? 'Not found.'),
      429 => RateLimitedException(
          message: message ?? 'Too many requests. Slow down.',
          code: code,
          retryAfterSeconds: envelope.retryAfter,
        ),
      501 => const FeatureUnavailableException(),
      503 => ServiceUnavailableException(
          message ?? "We're undergoing maintenance. Back shortly.",
        ),
      final s when s != null && s >= 500 =>
        ServerException(message ?? "Server error. We're on it."),
      _ => ApiException(
          message ?? 'Unexpected error.',
          statusCode: status,
          code: code,
        ),
    };

    handler.reject(err.copyWith(error: mapped));
  }

  _Envelope _envelope(Response? response) {
    final data = response?.data;
    if (data is! Map) return const _Envelope();
    // Sahachiel: read each field defensively instead of blanket `as` casts. A
    // single wrong-typed field (e.g. {"error": 123}) used to throw inside the
    // try and get swallowed, discarding the WHOLE envelope - including any valid
    // message/code sitting next to it. Now a malformed field is just skipped.
    String? str(String key) {
      final v = data[key];
      return v is String ? v : null;
    }

    int? intOf(String key) {
      final v = data[key];
      return v is num ? v.toInt() : null;
    }

    return _Envelope(
      message: str('error') ?? str('message'),
      code: str('code'),
      retryAfter: intOf('retryAfter'),
    );
  }
}

class _Envelope {
  const _Envelope({this.message, this.code, this.retryAfter});
  final String? message;
  final String? code;
  final int? retryAfter;
}
