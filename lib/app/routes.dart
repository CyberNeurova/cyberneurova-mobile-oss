import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/platform/platform_flags.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_bootstrap_screen.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/archived_chats_screen.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_search_screen.dart';
import 'package:cyberneurova_mobile/features/legal/presentation/screens/privacy_consent_screen.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/screens/chat_detail_screen.dart';
import 'package:cyberneurova_mobile/features/images/presentation/screens/image_generate_screen.dart';
import 'package:cyberneurova_mobile/features/capabilities/presentation/screens/capabilities_screen.dart';
import 'package:cyberneurova_mobile/features/images/presentation/screens/image_detail_screen.dart';
import 'package:cyberneurova_mobile/features/media/presentation/media_screen.dart';
import 'package:cyberneurova_mobile/features/memory/presentation/screens/memory_screen.dart';
import 'package:cyberneurova_mobile/features/research/presentation/screens/research_detail_screen.dart';
import 'package:cyberneurova_mobile/features/research/presentation/screens/research_list_screen.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/screens/billing_history_screen.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/screens/billing_result_screen.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/screens/checkout_webview_screen.dart';
import 'package:cyberneurova_mobile/features/payment/presentation/screens/plans_screen.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/screens/projects_screen.dart';
import 'package:cyberneurova_mobile/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:cyberneurova_mobile/features/remote/data/models/remote_device.dart';
import 'package:cyberneurova_mobile/features/remote/presentation/screens/remote_attach_screen.dart';
import 'package:cyberneurova_mobile/features/remote/presentation/screens/remote_devices_screen.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/screens/agents_screen.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/screens/bots_screen.dart';
import 'package:cyberneurova_mobile/features/bots/presentation/screens/bot_dm_screen.dart';
import 'package:cyberneurova_mobile/features/code/presentation/screens/code_sessions_screen.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/screens/adb_pairing_screen.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/screens/agent_environment_screen.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/screens/shell_sessions_screen.dart';
import 'package:cyberneurova_mobile/features/shell/presentation/screens/shell_session_screen.dart';
import 'package:cyberneurova_mobile/features/prompts/presentation/screens/prompts_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/language_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/settings_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/sessions_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/edit_profile_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/delete_account_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/change_email_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/change_password_screen.dart';
import 'package:cyberneurova_mobile/features/user/presentation/screens/usage_screen.dart';
import 'package:cyberneurova_mobile/core/perf/route_timing_observer.dart';
import 'package:cyberneurova_mobile/features/splash/presentation/splash_screen.dart';
import 'package:cyberneurova_mobile/shared/widgets/offline_banner.dart';

/// Keeps the device-backed surfaces off platforms that cannot run them.
///
/// The Agents hub already hides these cards, but a route is reachable by more
/// than a tap: a deep link, a notification, a restored navigation stack from a
/// build that had them. Landing on a terminal that can never start is worse
/// than not offering it, so those paths go back to the hub, which explains
/// why in one sentence.
/// Note: `agent-environment` is deliberately NOT in this set. It hosts the
/// local-model section, which is the one thing on that screen that works
/// without a device shell — pointing at a server on the user's own network
/// is a base URL, not a PTY. Gating the whole route removed a working
/// feature; the screen hides its own Android-only sections instead.
String? _deviceSurfacesOnly(BuildContext _, GoRouterState __) =>
    PlatformFlags.hasDeviceShell ? null : '/agents';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isSplash = state.matchedLocation == '/splash';
      // Splash always shows first — it decides where to go next based on
      // auth state once it resolves. Don't override.
      if (isSplash) return null;
      final isLoggedIn = ref.read(authProvider).valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      final loc = state.matchedLocation;

      // Public routes — Apple's guideline 5.1.1(v) forced this: the app can't
      // gate features that aren't account-based behind a login wall. So the
      // chat shell (composer visible, empty chat state, drawer, settings for
      // language/theme) is browsable without an account. The actual send +
      // any account-scoped screen (profile, projects, memory, delete-account)
      // still requires auth — the chat detail screen presents the login
      // sheet when an unauth user taps Send. Kimi / You.com / Perplexity all
      // ship this shape.
      const publicUnauthRoutes = <String>{'/chats', '/consent', '/settings'};
      final isPublicPrefix = loc.startsWith('/chats/');
      final isPublic = publicUnauthRoutes.contains(loc) || isPublicPrefix;

      if (!isLoggedIn && !isAuthRoute && !isPublic) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/chats';
      return null;
    },
    refreshListenable: _AuthListenable(ref),
    observers: [RouteTimingObserver()],
    routes: [
      // Splash — animated wordmark while auth resolves
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (_, state) => _fade(state, const SplashScreen()),
      ),
      // Auth
      GoRoute(
        path: '/auth/login',
        name: 'login',
        pageBuilder: (_, state) => _fade(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/auth/register',
        name: 'register',
        pageBuilder: (_, state) => _slideRight(state, const RegisterScreen()),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        name: 'forgot-password',
        pageBuilder: (_, state) =>
            _slideRight(state, const ForgotPasswordScreen()),
      ),

      // First-launch privacy disclosure (Apple 5.1.1(i)/5.1.2(i)). The
      // splash routes here on first launch; after the user taps I Agree
      // the pref is set and this route is never entered again on this
      // install.
      GoRoute(
        path: '/consent',
        name: 'consent',
        pageBuilder: (_, state) => _fade(state, const PrivacyConsentScreen()),
      ),

      // Main shell (offline banner wraps everything authed)
      ShellRoute(
        builder: (_, __, child) => OfflineBanner(child: child),
        routes: [
          // Chats list — drawer-based navigation, no bottom nav
          GoRoute(
            path: '/chats',
            name: 'chats',
            pageBuilder: (_, state) =>
                _fade(state, const ChatBootstrapScreen()),
            routes: [
              GoRoute(
                path: ':id',
                name: 'chat-detail',
                pageBuilder: (_, state) => _slideRight(
                  state,
                  ChatDetailScreen(chatId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),

          // Unified Media (Images + Videos with top tabs)
          GoRoute(
            path: '/media',
            name: 'media',
            pageBuilder: (_, state) =>
                _slideRight(state, const MediaScreen()),
          ),

          // Direct routes for image sub-screens (push from anywhere).
          // Video routes were removed 2026-06-05 with the video feature.
          GoRoute(
            path: '/image/generate',
            name: 'image-generate',
            // redesign pass: Imagine is a sibling home surface of Ask, not a
            // modal compose flow — a horizontal slide makes Ask ↔ Imagine
            // read as one surface swapping sideways.
            pageBuilder: (_, state) =>
                _slideRight(state, const ImageGenerateScreen()),
          ),
          GoRoute(
            path: '/image/:id',
            name: 'image-detail',
            pageBuilder: (_, state) => _fade(
              state,
              ImageDetailScreen(imageId: state.pathParameters['id']!),
            ),
          ),

          // Settings — a real route; sub-screens below push from it and
          // "back" returns here naturally (the old modal sheet + reopen
          // hack is gone).
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (_, state) =>
                _slideRight(state, const SettingsScreen()),
          ),

          // Remote control — attach to and drive a device from the phone
          // (mobile = controller). Pushed from Settings.
          GoRoute(
            path: '/remote-devices',
            name: 'remote-devices',
            pageBuilder: (_, state) =>
                _slideRight(state, const RemoteDevicesScreen()),
          ),
          GoRoute(
            path: '/remote-attach',
            name: 'remote-attach',
            pageBuilder: (_, state) {
              final device = state.extra;
              if (device is! RemoteDevice) {
                return _slideRight(state, const RemoteDevicesScreen());
              }
              return _slideRight(state, RemoteAttachScreen(device: device));
            },
          ),

          // Chat search — a full screen (not a SearchDelegate) so results
          // support the same long-press multi-select as the drawer.
          GoRoute(
            path: '/chat-search',
            name: 'chat-search',
            pageBuilder: (_, state) =>
                _slideRight(state, const ChatSearchScreen()),
          ),

          // Settings → Archived chats.
          GoRoute(
            path: '/archived-chats',
            name: 'archived-chats',
            pageBuilder: (_, state) =>
                _slideRight(state, const ArchivedChatsScreen()),
          ),

          // Profile / settings sub-screens (pushed from /settings).
          GoRoute(
            path: '/profile-edit',
            name: 'profile-edit',
            pageBuilder: (_, state) =>
                _slideRight(state, const EditProfileScreen()),
          ),
          GoRoute(
            path: '/profile-language',
            name: 'profile-language',
            pageBuilder: (_, state) =>
                _slideRight(state, const LanguageScreen()),
          ),
          GoRoute(
            path: '/profile-sessions',
            name: 'profile-sessions',
            pageBuilder: (_, state) =>
                _slideRight(state, const SessionsScreen()),
          ),
          GoRoute(
            path: '/profile-delete',
            name: 'profile-delete',
            pageBuilder: (_, state) =>
                _slideRight(state, const DeleteAccountScreen()),
          ),
          GoRoute(
            path: '/profile-memory',
            name: 'profile-memory',
            pageBuilder: (_, state) =>
                _slideRight(state, const MemoryScreen()),
          ),
          GoRoute(
            path: '/profile-prompts',
            name: 'profile-prompts',
            pageBuilder: (_, state) =>
                _slideRight(state, const PromptsScreen()),
          ),
          GoRoute(
            path: '/profile-projects',
            name: 'profile-projects',
            pageBuilder: (_, state) =>
                _slideRight(state, const ProjectsScreen()),
            routes: [
              // Tapping a project opens its chats (the chevron's promise);
              // editing lives in the row's overflow menu.
              GoRoute(
                path: ':id',
                name: 'project-detail',
                pageBuilder: (_, state) => _slideRight(
                  state,
                  ProjectDetailScreen(
                      projectId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/profile-capabilities',
            name: 'profile-capabilities',
            pageBuilder: (_, state) =>
                _slideRight(state, const CapabilitiesScreen()),
          ),
          GoRoute(
            path: '/usage',
            name: 'usage',
            pageBuilder: (_, state) =>
                _slideRight(state, const UsageScreen()),
          ),
          GoRoute(
            path: '/profile-change-password',
            name: 'profile-change-password',
            pageBuilder: (_, state) =>
                _slideRight(state, const ChangePasswordScreen()),
          ),
          GoRoute(
            path: '/profile-change-email',
            name: 'profile-change-email',
            pageBuilder: (_, state) =>
                _slideRight(state, const ChangeEmailScreen()),
          ),

          // Research center
          // Agents hub → Research + Code workspaces.
          GoRoute(
            path: '/agents',
            name: 'agents',
            pageBuilder: (_, state) =>
                _slideRight(state, const AgentsScreen()),
            routes: [
              // Shared by all three agent surfaces: the distro installed here
              // is the environment Console, Code and Research all run in.
              GoRoute(
                path: 'environment',
                name: 'agent-environment',
                pageBuilder: (_, state) =>
                    _slideRight(state, const AgentEnvironmentScreen()),
              ),
              // Pairing the phone with its own wireless debugging, which is
              // how the agent reaches shell privileges without Shizuku.
              GoRoute(
                path: 'pair',
                name: 'adb-pairing',
            redirect: _deviceSurfacesOnly,
                pageBuilder: (_, state) =>
                    _slideRight(state, const AdbPairingScreen()),
              ),
            ],
          ),

          // Agent Contacts (bot-section) — DM AI contacts. Remote-control +
          // on-device runs are P2–P3. Entitlement (DM = paid, groups =
          // pro/pro_max) is enforced server-side; the screen surfaces the 403
          // if a free user opens a DM.
          GoRoute(
            path: '/bots',
            name: 'bots',
            pageBuilder: (_, state) => _slideRight(state, const BotsScreen()),
            routes: [
              GoRoute(
                path: 'room/:roomId',
                name: 'bot-dm',
                pageBuilder: (_, state) => _slideRight(
                  state,
                  BotDmScreen(
                    roomId: state.pathParameters['roomId']!,
                    title: state.uri.queryParameters['title'],
                    type: state.uri.queryParameters['type'],
                    agentId: state.uri.queryParameters['agentId'],
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/code',
            name: 'code',
            redirect: _deviceSurfacesOnly,
            pageBuilder: (_, state) =>
                _slideRight(state, const CodeSessionsScreen()),
          ),

          // Shell workspace — the terminal + agent surface. The list is a
          // sibling of Code/Research; the session screen is nested so back
          // returns to the list rather than the Agents hub.
          GoRoute(
            path: '/shell',
            name: 'shell',
            redirect: _deviceSurfacesOnly,
            pageBuilder: (_, state) =>
                _slideRight(state, const ShellSessionsScreen()),
            routes: [
              GoRoute(
                path: ':id',
                name: 'shell-session',
                pageBuilder: (_, state) => _slideRight(
                  state,
                  ShellSessionScreen(chatId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),

          GoRoute(
            path: '/research',
            name: 'research',
            pageBuilder: (_, state) =>
                _slideRight(state, const ResearchListScreen()),
            routes: [
              GoRoute(
                path: ':id',
                name: 'research-detail',
                pageBuilder: (_, state) => _slideRight(
                  state,
                  ResearchDetailScreen(
                      sessionId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),

          // Billing flow (Android / web only — iOS hides the entry points).
          GoRoute(
            path: '/billing-plans',
            name: 'billing-plans',
            pageBuilder: (_, state) =>
                _slideRight(state, const PlansScreen()),
          ),
          GoRoute(
            path: '/billing-history',
            name: 'billing-history',
            pageBuilder: (_, state) =>
                _slideRight(state, const BillingHistoryScreen()),
          ),
          GoRoute(
            path: '/billing-checkout',
            name: 'billing-checkout',
            pageBuilder: (_, state) => _slideUp(
              state,
              CheckoutWebviewScreen(
                tier: state.uri.queryParameters['tier'] ?? '',
                paymentMethod:
                    state.uri.queryParameters['method'] ?? 'crypto',
                isYearly:
                    state.uri.queryParameters['yearly'] == 'true',
              ),
            ),
          ),
          GoRoute(
            path: '/billing-result',
            name: 'billing-result',
            pageBuilder: (_, state) => _fade(
              state,
              BillingResultScreen(
                status: state.uri.queryParameters['status'] ?? 'failed',
              ),
            ),
          ),
        ],
      ),
    ],
  );
});

// ─── Page transitions ────────────────────────────────────────────────────────
//
// Exactly three, used consistently (see docs/REDESIGN.md "Motion tokens"):
//   _fade       → root swaps (splash→app, →login, consent, shell entry) and
//                 full-screen viewers (image detail). 200ms.
//   _slideRight → every forward push. Incoming slides from the right with a
//                 fade; the covered page parallax-shifts left. 250ms in /
//                 180ms out (exit faster than enter).
//   _slideUp    → modal compose flows only (checkout). 300ms.
// Don't add per-route custom transitions.

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

CustomTransitionPage<void> _slideRight(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (_, animation, secondary, child) {
      // iOS-style: incoming slides + fades; when covered by the next route,
      // this page parallax-shifts left so the pair reads as one surface
      // moving, not two unrelated screens swapping.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final secondaryCurved = CurvedAnimation(
        parent: secondary,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween(
          begin: Offset.zero,
          end: const Offset(-0.06, 0.0),
        ).animate(secondaryCurved),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.15, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        ),
      );
    },
  );
}

CustomTransitionPage<void> _slideUp(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0.0, 1.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      )),
      child: child,
    ),
  );
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}
