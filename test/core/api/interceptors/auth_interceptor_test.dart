import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cyberneurova_mobile/core/api/interceptors/auth_interceptor.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';

// Sahachiel: covers the security-critical AuthInterceptor - Bearer attach,
// skipAuth, and the transparent 401 refresh with its single-flight lock. The
// single-flight behaviour is the subtle one: the refresh token rotates on use,
// so two parallel 401s firing two refreshes would log the user out. Zero
// coverage before this.

class _MockSecureStorage extends Mock implements SecureStorage {}

class _MockDio extends Mock implements Dio {}

class _MockRequestHandler extends Mock implements RequestInterceptorHandler {}

class _MockErrorHandler extends Mock implements ErrorInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(Options());
    registerFallbackValue(
        DioException(requestOptions: RequestOptions(path: '/')));
  });

  late _MockSecureStorage storage;
  late _MockDio dio;
  late List<String?> rotated;
  late AuthInterceptor interceptor;

  setUp(() {
    storage = _MockSecureStorage();
    dio = _MockDio();
    rotated = <String?>[];
    interceptor = AuthInterceptor(
      storage: storage,
      dio: dio,
      onAccessTokenChanged: rotated.add,
    );
  });

  DioException err401(String path) {
    final ro = RequestOptions(path: path);
    return DioException(
      requestOptions: ro,
      response: Response<dynamic>(requestOptions: ro, statusCode: 401),
    );
  }

  /// What the refresh POST throws, shaped the way Dio delivers it. With no
  /// [status] the server never answered (no network, a timeout).
  DioException refreshError({int? status, DioExceptionType? type}) {
    final ro = RequestOptions(path: ApiConstants.AUTH_REFRESH);
    return DioException(
      requestOptions: ro,
      type: type ?? DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response<dynamic>(requestOptions: ro, statusCode: status),
    );
  }

  void stubRefreshThrows(DioException failure) {
    when(() => storage.getRefreshToken()).thenAnswer((_) async => 'refreshOld');
    when(() => dio.post<dynamic>(any(),
        data: any(named: 'data'),
        options: any(named: 'options'))).thenAnswer((_) async => throw failure);
    when(() => storage.clearAll()).thenAnswer((_) async {});
  }

  void stubRefreshAnswers(Map<String, dynamic> body) {
    when(() => storage.getRefreshToken()).thenAnswer((_) async => 'refreshOld');
    when(() => dio.post<dynamic>(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => Response<dynamic>(
              requestOptions: RequestOptions(path: ApiConstants.AUTH_REFRESH),
              statusCode: 200,
              data: body,
            ));
    when(() => storage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        )).thenAnswer((_) async {});
    when(() => storage.clearAll()).thenAnswer((_) async {});
  }

  group('onRequest', () {
    test('skips the auth header when extra.skipAuth is set', () async {
      final options = RequestOptions(path: '/x', extra: {'skipAuth': true});
      final handler = _MockRequestHandler();

      await interceptor.onRequest(options, handler);

      verify(() => handler.next(options)).called(1);
      verifyNever(() => storage.getAccessToken());
      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('attaches the Bearer token when one is stored', () async {
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok123');
      final options = RequestOptions(path: '/x');
      final handler = _MockRequestHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer tok123');
      verify(() => handler.next(options)).called(1);
    });
  });

  group('onError', () {
    test('forwards non-401 errors untouched', () async {
      final ro = RequestOptions(path: '/x');
      final input = DioException(
        requestOptions: ro,
        response: Response<dynamic>(requestOptions: ro, statusCode: 500),
      );
      final handler = _MockErrorHandler();

      await interceptor.onError(input, handler);

      verify(() => handler.next(input)).called(1);
      verifyNever(() => storage.getRefreshToken());
    });

    test('a 401 from the refresh endpoint clears storage and does not loop',
        () async {
      when(() => storage.clearAll()).thenAnswer((_) async {});
      final input = err401(ApiConstants.AUTH_REFRESH);
      final handler = _MockErrorHandler();

      await interceptor.onError(input, handler);

      verify(() => storage.clearAll()).called(1);
      verify(() => handler.next(input)).called(1);
      verifyNever(
        () => dio.post<dynamic>(any(),
            data: any(named: 'data'), options: any(named: 'options')),
      );
    });

    test('a 401 refreshes the token and retries the original request',
        () async {
      stubRefreshAnswers({'accessToken': 'newA', 'refreshToken': 'newR'});
      final retried = Response<dynamic>(
        requestOptions: RequestOptions(path: '/data'),
        statusCode: 200,
        data: 'ok',
      );
      when(() => dio.fetch<dynamic>(any())).thenAnswer((_) async => retried);

      final input = err401('/data');
      final handler = _MockErrorHandler();

      await interceptor.onError(input, handler);

      verify(() => storage.saveTokens(
            accessToken: 'newA',
            refreshToken: 'newR',
          )).called(1);
      expect(input.requestOptions.headers['Authorization'], 'Bearer newA');
      verify(() => dio.fetch<dynamic>(input.requestOptions)).called(1);
      verify(() => handler.resolve(retried)).called(1);
      expect(rotated, contains('newA'));
    });

    test('a refresh response without a new refresh token keeps the current one',
        () async {
      // A server that does not rotate refresh tokens answers with the access
      // token alone. That is a successful refresh, not a reason to log out.
      stubRefreshAnswers({'accessToken': 'newA'});
      final retried = Response<dynamic>(
        requestOptions: RequestOptions(path: '/data'),
        statusCode: 200,
        data: 'ok',
      );
      when(() => dio.fetch<dynamic>(any())).thenAnswer((_) async => retried);

      final handler = _MockErrorHandler();
      await interceptor.onError(err401('/data'), handler);

      verify(() => storage.saveTokens(
            accessToken: 'newA',
            refreshToken: 'refreshOld',
          )).called(1);
      verifyNever(() => storage.clearAll());
      verify(() => handler.resolve(retried)).called(1);
    });

    test('a retried request that still gets 401 is passed on, not refreshed',
        () async {
      // Real Dio sends the retried request back through this interceptor. If
      // the endpoint refuses even the fresh token, refreshing again would only
      // rotate the tokens and get refused again, round and round.
      stubRefreshAnswers({'accessToken': 'newA', 'refreshToken': 'newR'});
      when(() => dio.fetch<dynamic>(any())).thenAnswer((_) async =>
          Response<dynamic>(
              requestOptions: RequestOptions(path: '/data'),
              statusCode: 200,
              data: 'ok'));

      final first = err401('/data');
      await interceptor.onError(first, _MockErrorHandler());

      final ro = first.requestOptions;
      final again = DioException(
        requestOptions: ro,
        response: Response<dynamic>(requestOptions: ro, statusCode: 401),
      );
      final handler = _MockErrorHandler();
      await interceptor.onError(again, handler);

      verify(() => handler.next(again)).called(1);
      verify(() => dio.post<dynamic>(any(),
          data: any(named: 'data'), options: any(named: 'options'))).called(1);
      verify(() => dio.fetch<dynamic>(any())).called(1);
    });

    test('a 401 with no stored refresh token surfaces the error', () async {
      when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
      final input = err401('/data');
      final handler = _MockErrorHandler();

      await interceptor.onError(input, handler);

      verify(() => handler.next(input)).called(1);
      verifyNever(() => dio.fetch<dynamic>(any()));
      expect(rotated, isEmpty);
    });

    // The refresh endpoint answering "no" is the only thing that ends the
    // session: the refresh token is dead, so keeping it would be pointless.
    for (final status in [400, 401, 403]) {
      test('a refresh rejected with $status clears storage and notifies null',
          () async {
        stubRefreshThrows(refreshError(status: status));

        final input = err401('/data');
        final handler = _MockErrorHandler();

        await interceptor.onError(input, handler);

        verify(() => storage.clearAll()).called(1);
        expect(rotated, [null]);
        verify(() => handler.next(input)).called(1);
        verifyNever(() => dio.fetch<dynamic>(any()));
      });
    }

    // A refresh that never got a verdict says nothing about the session. The
    // refresh token is still good, so wiping it would sign the user out over
    // a dropped connection or a deploy. The request fails with what actually
    // went wrong, and the next 401 simply tries the refresh again.
    for (final (label, failure) in [
      ('no network', refreshError(type: DioExceptionType.connectionError)),
      ('a timeout', refreshError(type: DioExceptionType.connectionTimeout)),
      ('a 502', refreshError(status: 502)),
      ('a 503', refreshError(status: 503)),
      ('a 429', refreshError(status: 429)),
    ]) {
      test('a refresh failing with $label keeps the tokens and surfaces it',
          () async {
        stubRefreshThrows(failure);

        final input = err401('/data');
        final handler = _MockErrorHandler();

        await interceptor.onError(input, handler);

        verifyNever(() => storage.clearAll());
        expect(rotated, isEmpty);
        verify(() => handler.next(failure)).called(1);
        verifyNever(() => handler.next(input));
        verifyNever(() => dio.fetch<dynamic>(any()));
      });
    }

    test('an unreadable refresh response keeps the tokens and is not a 401',
        () async {
      // A 200 without an access token cannot be used, but it is not the
      // server rejecting the session either. Handing on the original 401
      // would read as signed out at cold start while the tokens are kept.
      stubRefreshAnswers({'unexpected': true});

      final input = err401('/data');
      final handler = _MockErrorHandler();

      await interceptor.onError(input, handler);

      verifyNever(() => storage.clearAll());
      expect(rotated, isEmpty);
      verifyNever(() => handler.next(input));
      verify(() => handler.next(any(
            that: isA<DioException>()
                .having((e) => e.type, 'type', DioExceptionType.unknown)
                .having((e) => e.response, 'response', isNull),
          ))).called(1);
      verifyNever(() => dio.fetch<dynamic>(any()));
    });

    test('concurrent 401s share a single refresh call (single-flight)',
        () async {
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => 'refreshOld');
      final postCompleter = Completer<Response<dynamic>>();
      when(() => dio.post<dynamic>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) => postCompleter.future);
      when(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
          )).thenAnswer((_) async {});
      when(() => dio.fetch<dynamic>(any())).thenAnswer((_) async =>
          Response<dynamic>(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: 200,
              data: 'ok'));

      // Fire two 401s before the refresh resolves so both hit the shared lock.
      final f1 = interceptor.onError(err401('/a'), _MockErrorHandler());
      final f2 = interceptor.onError(err401('/b'), _MockErrorHandler());
      await Future<void>.delayed(Duration.zero);
      postCompleter.complete(Response<dynamic>(
        requestOptions: RequestOptions(path: ApiConstants.AUTH_REFRESH),
        statusCode: 200,
        data: {'accessToken': 'newA', 'refreshToken': 'newR'},
      ));
      await Future.wait([f1, f2]);

      verify(() => dio.post<dynamic>(any(),
          data: any(named: 'data'), options: any(named: 'options'))).called(1);
    });
  });
}
