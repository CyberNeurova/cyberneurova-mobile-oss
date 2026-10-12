import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/features/auth/data/models/user_model.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/chat_model.dart';
import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_bootstrap_screen.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';

/// Retry on the launch screen has to ask the server again.
///
/// A chat-list load that fails leaves the provider holding the error, and
/// awaiting it again hands back that same error without a request. Retry did
/// exactly that, so a network blip during sign-in, with no saved list to fall
/// back on, left the user on "Couldn't load your chats" with a button that
/// sent nothing however often they pressed it. The screen has no drawer or
/// back route, so it was the only way forward.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Retry re-fetches the list and opens the chat', (tester) async {
    final repo = _FlakyRepo();
    final router = GoRouter(
      initialLocation: '/chats',
      routes: [
        GoRoute(
          path: '/chats',
          name: 'chats',
          builder: (_, __) => const ChatBootstrapScreen(),
          routes: [
            GoRoute(
              path: ':id',
              name: 'chat-detail',
              builder: (_, s) => Text('chat:${s.pathParameters['id']}'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_SignedIn.new),
        chatRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
      ),
    ));
    await _settle(tester);

    expect(find.text("Couldn't load your chats"), findsOneWidget);
    expect(repo.calls, 4, reason: 'one request per section');

    // The connection is back.
    repo.failing = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);

    expect(repo.calls, 8, reason: 'Retry asks every section again');
    expect(find.text('chat:fresh'), findsOneWidget,
        reason: 'and lands in the empty chat the server now returns');
  });
}

/// Pumps frames until the async work settles. `pumpAndSettle` cannot be used:
/// the loading state shows an indeterminate spinner that never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _SignedIn extends AuthNotifier {
  @override
  Future<UserModel?> build() async =>
      const UserModel(id: 'u1', email: 'u1@example.test');
}

/// Fails every list request while [failing], then answers with one empty chat.
class _FlakyRepo implements ChatRepository {
  bool failing = true;
  int calls = 0;

  @override
  Future<ChatListResponse> listChats({String? cursor, String? section}) async {
    calls++;
    if (failing) throw const NetworkException();
    return ChatListResponse(
      chats: [if (section == 'chat') const ChatModel(id: 'fresh')],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
