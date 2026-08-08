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
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => 'refreshOld');
      when(() => dio.post<dynamic>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) async => Response<dynamic>(
                requestOptions: RequestOptions(path: ApiConstants.AUTH_REFRESH),
                statusCode: 200,
                data: {'accessToken': 'newA', 'refreshToken': 'newR'},
              ));
      when(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
          )).thenAnswer((_) async {});
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
      verify(() => handler.resolve(retried)).called(1);
      expect(rotated, contains('newA'));
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

    test('a failed refresh clears storage and notifies a null token', () async {
      when(() => storage.getRefreshToken())
          .thenAnswer((_) async => 'refreshOld');
      when(() => dio.post<dynamic>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) async =>
              throw DioException(requestOptions: RequestOptions(path: '/')));
      when(() => storage.clearAll()).thenAnswer((_) async {});

      final input = err401('/data');
      final handler = _MockErrorHandler();

      await interceptor.onError(input, handler);

      verify(() => storage.clearAll()).called(1);
      expect(rotated, contains(null));
      verify(() => handler.next(input)).called(1);
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
          data: any(named: 'data'),
          options: any(named: 'options'))).called(1);
    });
  });
}
