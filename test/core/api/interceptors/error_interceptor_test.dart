import 'dart:convert';
import 'dart:typed_data';

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

/// Answers every request with one canned HTTP response, so a test can drive a
/// real Dio — its real response transformer and interceptor chain — without
/// opening a socket.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(body, status, headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      });

  @override
  void close({bool force = false}) {}
}

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

  group('ErrorInterceptor byte bodies (ResponseType.bytes)', () {
    // TTS asks for its audio as bytes, and Dio applies the response type to
    // error responses too: a 403 from /tts reaches the interceptor as the raw
    // UTF-8 of the JSON envelope, not a Map. Only Maps were read, so every
    // byte request lost code, message and retryAfter — a free-tier Listen
    // threw ForbiddenException with no code, the TIER_REQUIRED check never
    // matched, and the voice paywall never opened.
    Uint8List bytesOf(Object json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));

    test('403 envelope as bytes maps exactly like the same envelope as a Map',
        () {
      const body = {
        'error': 'Voice is a paid feature.',
        'code': 'TIER_REQUIRED',
      };
      final fromMap = mapError(makeError(status: 403, data: body));
      final fromBytes = mapError(makeError(status: 403, data: bytesOf(body)));

      expect(fromBytes, isA<ForbiddenException>());
      expect(fromBytes.code, 'TIER_REQUIRED');
      expect(fromBytes.message, 'Voice is a paid feature.');
      expect(fromBytes.code, fromMap.code);
      expect(fromBytes.message, fromMap.message);
    });

    test('429 envelope as bytes keeps code and retryAfter', () {
      const body = {
        'error': 'Slow down.',
        'code': 'RATE_LIMITED',
        'retryAfter': 60,
      };
      final fromMap =
          mapError(makeError(status: 429, data: body)) as RateLimitedException;
      final fromBytes = mapError(makeError(status: 429, data: bytesOf(body)));

      expect(fromBytes, isA<RateLimitedException>());
      fromBytes as RateLimitedException;
      expect(fromBytes.code, 'RATE_LIMITED');
      expect(fromBytes.retryAfterSeconds, 60);
      expect(fromBytes.message, 'Slow down.');
      expect(fromBytes.retryAfterSeconds, fromMap.retryAfterSeconds);
      expect(fromBytes.message, fromMap.message);
    });

    test('402 envelope as bytes keeps the server message', () {
      final e = mapError(makeError(
        status: 402,
        data: bytesOf({'error': 'Voice minutes used up for this month.'}),
      ));
      expect(e, isA<QuotaExceededException>());
      expect(e.message, 'Voice minutes used up for this month.');
    });

    test('bytes that are not a JSON object fall back to the defaults', () {
      // The interceptor must never throw while reading a body: if it did, the
      // caller would get Dio's own error instead of a typed AppException.
      final bodies = <String, List<int>>{
        'audio': Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0]),
        'invalid UTF-8': Uint8List.fromList([0xFF, 0xFE, 0xC3]),
        'HTML page': utf8.encode('<html>502 Bad Gateway</html>'),
        'JSON array': utf8.encode('[1, 2, 3]'),
        'JSON string': utf8.encode('"TIER_REQUIRED"'),
        'empty': Uint8List(0),
      };
      for (final entry in bodies.entries) {
        final e = mapError(makeError(status: 403, data: entry.value));
        expect(e, isA<ForbiddenException>(), reason: entry.key);
        expect(e.message, 'Access denied.', reason: entry.key);
        expect(e.code, isNull, reason: entry.key);
      }
    });

    test('a real bytes request through Dio surfaces TIER_REQUIRED', () async {
      // The cases above hand the interceptor bytes directly. This one lets
      // Dio produce them, so it breaks if Dio stops delivering a bytes error
      // body this way or the interceptor stops decoding it. The request copies
      // VoiceRepository's /tts options rather than calling it, so changes
      // there are not tracked here.
      final dio = Dio()
        ..httpClientAdapter = _CannedAdapter(
          403,
          jsonEncode({
            'error': 'Voice is a paid feature.',
            'code': 'TIER_REQUIRED',
          }),
        )
        ..interceptors.add(ErrorInterceptor());

      DioException? caught;
      try {
        await dio.post<List<int>>(
          '/tts',
          data: {'text': 'hello'},
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Content-Type': 'application/json'},
          ),
        );
      } on DioException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.response?.data, isA<List<int>>(),
          reason: 'Dio really does hand an error body over as bytes here');
      expect(caught.error, isA<ForbiddenException>());
      final mapped = caught.error as ForbiddenException;
      expect(mapped.code, 'TIER_REQUIRED');
      expect(mapped.message, 'Voice is a paid feature.');
    });
  });
}
