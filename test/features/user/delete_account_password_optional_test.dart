import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cyberneurova_mobile/core/api/api_client.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/features/user/data/repositories/user_repository.dart';

/// Account deletion must work for a user who has no password.
///
/// Apple 5.1.1(v): an app that offers account creation must let the user delete
/// the account — all of them, not just the ones created with email + password.
/// A Google or Apple sign-in user never set a password, so a delete flow that
/// REQUIRES one locks them out of removing their own account, which is a
/// rejection and, worse, a real dead end for the user.
///
/// The server contract is `{password?, confirmText:"DELETE MY ACCOUNT"}` — the
/// confirm phrase is the guard and the password is verified only when the
/// account has one. This pins the client to that contract: an absent password
/// is OMITTED (not sent as an empty string, which the server would read as "the
/// password is the empty string" and reject), while the confirm phrase is
/// always sent.
class _MockApiClient extends Mock implements ApiClient {}

void main() {
  late _MockApiClient client;
  late UserRepository repo;
  late Map<String, dynamic> sentBody;

  Response<dynamic> ok() => Response<dynamic>(
        requestOptions: RequestOptions(path: ApiConstants.USER_DELETE),
        statusCode: 200,
      );

  setUp(() {
    client = _MockApiClient();
    repo = UserRepository(client);
    when(() => client.delete<dynamic>(any(), data: any(named: 'data')))
        .thenAnswer((invocation) async {
      sentBody = Map<String, dynamic>.from(
          invocation.namedArguments[#data] as Map);
      return ok();
    });
  });

  test('the confirm phrase is always sent', () async {
    await repo.deleteAccount(password: 'hunter2');
    expect(sentBody['confirmText'], 'DELETE MY ACCOUNT');
  });

  test('a real password is forwarded for accounts that have one', () async {
    await repo.deleteAccount(password: 'hunter2');
    expect(sentBody['password'], 'hunter2');
  });

  group('a social sign-in user (no password) can still delete', () {
    test('null password is omitted, not sent blank', () async {
      await repo.deleteAccount();
      expect(sentBody.containsKey('password'), isFalse,
          reason: 'sending "password": null/"" reads as a wrong password to '
              'the server; the key must be absent so it verifies the confirm '
              'phrase alone');
      expect(sentBody['confirmText'], 'DELETE MY ACCOUNT');
    });

    test('an empty password is treated as no password', () async {
      // The delete screen passes the field text straight through; an untouched
      // field is ''. That must behave exactly like null, or the fix does not
      // reach the screen it was made for.
      await repo.deleteAccount(password: '');
      expect(sentBody.containsKey('password'), isFalse);
      expect(sentBody['confirmText'], 'DELETE MY ACCOUNT');
    });
  });
}
