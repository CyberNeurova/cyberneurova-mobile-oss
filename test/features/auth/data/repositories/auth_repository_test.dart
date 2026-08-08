import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';
import 'package:cyberneurova_mobile/features/auth/data/repositories/auth_repository.dart';

// Sahachiel: first real unit test in the repo. It locks the body-based
// DELETE /user/sessions contract (OPEN_ISSUES #21) so nobody "fixes" it back
// to the non-existent path-based `/user/sessions/:id` route server-side.

class _MockApiClient extends Mock implements ApiClient {}

class _MockSecureStorage extends Mock implements SecureStorage {}

class _MockRef extends Mock implements Ref {}

void main() {
  late _MockApiClient client;
  late AuthRepository repo;

  // A throwaway Response so the awaited `delete` call resolves; revokeSession
  // ignores the body, we only care about what was sent.
  Response<dynamic> ok() => Response<dynamic>(
        requestOptions: RequestOptions(path: ApiConstants.USER_SESSIONS),
        statusCode: 200,
      );

  setUp(() {
    client = _MockApiClient();
    // _storage and _ref are never touched by the session-revoke methods, so
    // bare mocks are enough — no stubbing required.
    repo = AuthRepository(client, _MockSecureStorage(), _MockRef());

    when(() => client.delete<dynamic>(any(), data: any(named: 'data')))
        .thenAnswer((_) async => ok());
  });

  group('AuthRepository session revoke', () {
    test('revokeSession hits the collection route with a {sessionId} body',
        () async {
      await repo.revokeSession('sess_123');

      final captured = verify(
        () => client.delete<dynamic>(
          captureAny(),
          data: captureAny(named: 'data'),
        ),
      ).captured;

      expect(captured[0], ApiConstants.USER_SESSIONS);
      expect(captured[1], {'sessionId': 'sess_123'});
    });

    test('revokeAllOtherSessions hits the collection route with {revokeAll}',
        () async {
      await repo.revokeAllOtherSessions();

      final captured = verify(
        () => client.delete<dynamic>(
          captureAny(),
          data: captureAny(named: 'data'),
        ),
      ).captured;

      expect(captured[0], ApiConstants.USER_SESSIONS);
      expect(captured[1], {'revokeAll': true});
    });

    test('revokeSession never uses a path-based /user/sessions/:id route',
        () async {
      await repo.revokeSession('sess_123');

      final path = verify(
        () => client.delete<dynamic>(
          captureAny(),
          data: any(named: 'data'),
        ),
      ).captured.single as String;

      expect(path, isNot(contains('sess_123')));
    });
  });

  // Sahachiel: getMe + listSessions hand-parse the response. getMe runs on every
  // cold start; a present-but-non-map `user` used to CastError-crash launch, and
  // listSessions' lazy `.cast<Map>()` threw on iteration of a mixed list. Lock
  // the unwrap + the defensive degradation.
  group('AuthRepository.getMe / listSessions parsing', () {
    test('getMe unwraps {user:{...}}', () async {
      when(() => client.get<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: ApiConstants.AUTH_ME),
          statusCode: 200,
          data: {
            'user': {'id': 'u1', 'email': 'a@b.co'},
          },
        ),
      );

      final u = await repo.getMe();
      expect(u.id, 'u1');
      expect(u.email, 'a@b.co');
    });

    test('getMe falls back without crashing when user is a non-map', () async {
      when(() => client.get<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: ApiConstants.AUTH_ME),
          statusCode: 200,
          data: {'id': 'u2', 'email': 'c@d.co', 'user': 'oops'},
        ),
      );

      final u = await repo.getMe();
      expect(u.id, 'u2');
    });

    test('listSessions returns rows and skips non-map entries', () async {
      when(() => client.get<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: ApiConstants.USER_SESSIONS),
          statusCode: 200,
          data: {
            'sessions': [
              {'id': 's1'},
              null,
              'garbage',
              {'id': 's2'},
            ],
          },
        ),
      );

      final sessions = await repo.listSessions();
      expect(sessions.map((s) => s['id']).toList(), ['s1', 's2']);
    });

    test('listSessions tolerates a non-list sessions field', () async {
      when(() => client.get<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: ApiConstants.USER_SESSIONS),
          statusCode: 200,
          data: {'sessions': 'nope'},
        ),
      );

      expect(await repo.listSessions(), isEmpty);
    });
  });
}
