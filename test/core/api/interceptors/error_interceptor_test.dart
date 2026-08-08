import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cyberneurova_mobile/core/api/interceptors/error_interceptor.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';

// Sahachiel: locks the DioException -> typed AppException mapping. This is
// fragile routing logic with branches (404 HTML-vs-JSON, 429 retryAfter, TLS)
// and had zero coverage; a refactor could silently re-map a status and the UI
// would show the wrong state. Also pins the defensive _envelope parsing.

class _MockErrorHandler extends Mock implements ErrorInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      DioException(requestOptions: RequestOptions(path: '/')),
    );
  });

  DioException makeError({
    int? status,
    dynamic data,
    Map<String, List<String>>? headers,
    DioExceptionType type = DioExceptionType.badResponse,
  }) {
    final ro = RequestOptions(path: '/x');
    return DioException(
      requestOptions: ro,
      type: type,
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: ro,
              statusCode: status,
              data: data,
              headers: headers == null ? null : Headers.fromMap(headers),
            ),
    );
  }

  /// Run the interceptor and return the AppException it rejected with.
  AppException mapError(DioException input) {
    final handler = _MockErrorHandler();
    ErrorInterceptor().onError(input, handler);
    final captured =
        verify(() => handler.reject(captureAny())).captured.single
            as DioException;
    return captured.error as AppException;
  }

  group('ErrorInterceptor connectivity mapping', () {
    test('connectionError -> NetworkException', () {
      expect(mapError(makeError(type: DioExceptionType.connectionError)),
          isA<NetworkException>());
    });

    test('receiveTimeout -> TimeoutException', () {
      expect(mapError(makeError(type: DioExceptionType.receiveTimeout)),
          isA<TimeoutException>());
    });

    test('badCertificate -> CertificateException', () {
      expect(mapError(makeError(type: DioExceptionType.badCertificate)),
          isA<CertificateException>());
    });

    test('cancel is passed through, never wrapped', () {
      final handler = _MockErrorHandler();
      final input = makeError(type: DioExceptionType.cancel);
      ErrorInterceptor().onError(input, handler);
      verify(() => handler.next(input)).called(1);
      verifyNever(() => handler.reject(any()));
    });
  });

  group('ErrorInterceptor HTTP status mapping', () {
    test('401 -> UnauthorizedException', () {
      expect(mapError(makeError(status: 401)), isA<UnauthorizedException>());
    });

    test('402 -> QuotaExceededException', () {
      expect(mapError(makeError(status: 402)), isA<QuotaExceededException>());
    });

    test('403 -> ForbiddenException', () {
      expect(mapError(makeError(status: 403)), isA<ForbiddenException>());
    });

    test('500 -> ServerException', () {
      expect(mapError(makeError(status: 500)), isA<ServerException>());
    });

    test('503 -> ServiceUnavailableException', () {
      expect(mapError(makeError(status: 503)), isA<ServiceUnavailableException>());
    });

    test('429 carries retryAfter from the envelope', () {
      final e = mapError(makeError(status: 429, data: {'retryAfter': 30}));
      expect(e, isA<RateLimitedException>());
      expect((e as RateLimitedException).retryAfterSeconds, 30);
    });
  });

  group('ErrorInterceptor 404 feature-vs-resource', () {
    test('404 with a JSON envelope -> NotFoundException', () {
      final e = mapError(makeError(
        status: 404,
        headers: {
          'content-type': ['application/json'],
        },
        data: {'error': 'gone'},
      ));
      expect(e, isA<NotFoundException>());
    });

    test('404 with an HTML page -> FeatureUnavailableException', () {
      final e = mapError(makeError(
        status: 404,
        headers: {
          'content-type': ['text/html'],
        },
        data: '<html>not found</html>',
      ));
      expect(e, isA<FeatureUnavailableException>());
    });
  });

  group('ErrorInterceptor envelope parsing (defensive casts)', () {
    test('a wrong-typed field no longer discards the whole envelope', () {
      // {"error": 123} used to throw on the `as String` cast and get swallowed,
      // dropping the valid "message" alongside it. Now error is skipped and the
      // message survives.
      final e = mapError(makeError(
        status: 400,
        data: {'error': 123, 'message': 'real message'},
      ));
      expect(e, isA<ApiException>());
      expect((e as ApiException).message, 'real message');
    });

    test('a string error field is used as the message', () {
      final e = mapError(makeError(
        status: 400,
        data: {'error': 'bad input', 'code': 'INVALID'},
      ));
      expect((e as ApiException).message, 'bad input');
      expect(e.code, 'INVALID');
    });
  });
}
