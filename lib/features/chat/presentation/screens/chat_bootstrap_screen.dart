import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';

/// Lands the user in a real chat as soon as the app opens. There is no
/// "welcome" screen — that pattern had two competing composers and
/// two competing model pickers. Now: most-recent chat if one exists,
/// otherwise a fresh chat. If the list fetch fails, show retry.
class ChatBootstrapScreen extends ConsumerStatefulWidget {
  const ChatBootstrapScreen({super.key});

  @override
  ConsumerState<ChatBootstrapScreen> createState() =>
      _ChatBootstrapScreenState();
}

class _ChatBootstrapScreenState
    extends ConsumerState<ChatBootstrapScreen> {
  String? _error;

  /// True from the moment routing starts until it finishes or fails, so the
  /// sign-in listener below cannot start a second one on top of the first.
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Skip bootstrap for unauthenticated users — the /chats route is a
      // public shell under Apple's 5.1.1(v) compliance shape, and the
      // chatList/chatCreate API calls require auth. We render the welcome
      // shell directly in build().
      if (ref.read(authProvider).valueOrNull == null) return;
      _route();
    });
  }

  Future<void> _route() async {
    if (_routing) return;
    _routing = true;
    setState(() => _error = null);
    try {
      // Always land in "fresh chat mode" on cold launch — user-requested
      // 2026-06-18. reuseOrCreateEmptyChat picks an existing empty chat
      // (`messageCount == 0`, not blacklisted — blacklisted chats have
      // 403'd this session and picking one would loop bootstrap → 403 →
      // bounce → bootstrap forever) and only mints a new record when none
      // exists. Shared with every other new-chat trigger.
      final chatId =
          (await ref.read(chatListProvider.notifier).reuseOrCreateEmptyChat())
              .id;

      if (!mounted) return;
      // `go` not `push` — bootstrap should not stay on the back stack.
      context.goNamed(
        'chat-detail',
        pathParameters: {'id': chatId},
      );
    } catch (e) {
      // Sahachiel: first screen after login — never leak a raw Dio/exception
      // string here; map to a clean localized message.
      if (mounted) setState(() => _error = userMessageFor(context, e));
    } finally {
      _routing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Signing in while this screen is already open has to start the bootstrap.
    //
    // initState decides once, and at that point an unauthenticated visitor is
    // shown the welcome shell and routing is skipped — correctly. But when
    // they then sign in, `build` re-runs, `user` is no longer null, and the
    // skeleton renders with nothing behind it: _route() was never called and
    // nothing was going to call it. Observed on device — Google sign-in
    // succeeded and the app sat on the loading skeleton indefinitely; only
    // killing and relaunching it (so initState ran with a session) recovered.
    ref.listen(authProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before == null && after != null) _route();
    });

    final user = ref.watch(authProvider).valueOrNull;
    // Unauthenticated: show a static welcome shell with a composer, drawer,
    // and settings entry. The composer's Send bounces to /auth/login (Kimi
    // pattern) — satisfies Apple 5.1.1(v) by making the chat shell freely
    // browsable while keeping the actual send-and-receive gated on account.
    if (user == null) {
      return const _UnauthWelcomeShell();
    }
    // While resolving the target chat, render the chat-detail shell as a
    // skeleton (app bar + composer ghost) instead of a bare spinner — the
    // 200ms fade into the real chat then reads as content filling in, not
    // as a third distinct loading screen (docs/REDESIGN.md "Boot & auth").
    return Scaffold(
      appBar: _error != null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const CnShimmer(width: 120, height: 16, radius: 8),
              centerTitle: true,
            ),
      body: SafeArea(
        child: _error != null
            ? Center(child: _BootstrapError(error: _error!, onRetry: _route))
            : const Column(
                children: [
                  Expanded(child: SizedBox.shrink()),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: CnShimmer(
                              width: double.infinity,
                              height: 48,
                              radius: 24),
                        ),
                        SizedBox(width: 8),
                        CnShimmer(width: 44, height: 44, radius: 22),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Kimi-style shell for unauthenticated visitors. Everything you'd see in a
/// real chat detail — drawer with Sign in, model chip, hero prompt, composer
/// field — but no chat state is loaded and Send routes to login.
class _UnauthWelcomeShell extends StatefulWidget {
  const _UnauthWelcomeShell();

  @override
  State<_UnauthWelcomeShell> createState() => _UnauthWelcomeShellState();
}

class _UnauthWelcomeShellState extends State<_UnauthWelcomeShell> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bounceToLogin() async {
    HapticFeedback.mediumImpact();
    // `goNamed` REPLACED the stack, so the sign-in wall became the only route
    // and hardware back from it left the app — a new user who typed a question
    // and hesitated landed on their launcher. Verified on device. A sheet
    // leaves this screen mounted underneath, so back dismisses it and what
    // they typed is still in the box.
    final signedIn = await showLoginSheet(context);
    if (!signedIn || !mounted) return;

    // Carry the question through. They typed it before they had an account;
    // making them type it again is the app forgetting the only thing it had
    // been told.
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ProviderScope.containerOf(context)
          .read(pendingFirstMessageProvider.notifier)
          .state = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'CyberNeurova',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _bounceToLogin,
            child: const Text('Sign in'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 32, color: cs.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Ask CyberNeurova anything',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to start chatting.',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onTap: _bounceToLogin,
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: 'Message CyberNeurova…',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_upward_rounded,
                          color: cs.onPrimary),
                      onPressed: _bounceToLogin,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            "Couldn't load your chats",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
