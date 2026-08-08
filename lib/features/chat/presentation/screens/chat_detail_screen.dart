import 'package:cyberneurova_mobile/core/errors/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/attachments_provider.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/agent_activity_strip.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_composer.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/chat_options_menu.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/jump_to_bottom_pill.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/message_bubble.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/typing_indicator.dart';
import 'package:cyberneurova_mobile/features/chat/presentation/widgets/welcome_hint.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/providers/device_executor_provider.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/surface_welcome.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:cyberneurova_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:cyberneurova_mobile/l10n/generated/app_localizations.dart';
import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';
import 'package:cyberneurova_mobile/shared/widgets/ask_imagine_switch.dart';
import 'package:cyberneurova_mobile/shared/widgets/cn_shimmer.dart';
import 'package:cyberneurova_mobile/core/connectivity/connectivity_provider.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/shared/widgets/error_view.dart';
import 'package:cyberneurova_mobile/shared/widgets/glass_surface.dart';
import 'package:cyberneurova_mobile/shared/widgets/paywall_sheet.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _pendingHandled = false;

  /// While true, streaming tokens keep the view pinned to the newest message.
  /// Scrolling up detaches (so reading is never yanked back down); returning
  /// to within [_bottomSlackPx] of the end — or tapping the jump pill, or
  /// sending a message — re-attaches.
  bool _stickToBottom = true;

  /// Live height of the floating composer, reported by [ChatComposer]. Used
  /// as the message list's bottom inset. Seeded with a sensible idle height
  /// so the very first frame isn't laid out under the glass.
  double _composerHeight = 132;

  /// Counts in-flight programmatic scrolls so their scroll notifications
  /// don't get mistaken for the user detaching.
  int _activeAutoScrolls = 0;
  static const _bottomSlackPx = 80.0;

  @override
  void initState() {
    super.initState();
    // If the user came from the New Chat welcome with a typed prompt,
    // auto-send it as soon as the chat detail is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Clear any error snackbar lingering from the previously-open chat.
      // Snackbars live on the app-level Messenger, so without this the
      // "Model returned no response" toast follows the user into the next
      // chat and blocks interaction.
      ScaffoldMessenger.of(context).clearSnackBars();
      if (_pendingHandled) return;
      final pending = ref.read(pendingFirstMessageProvider);
      if (pending != null && pending.isNotEmpty) {
        _pendingHandled = true;
        ref.read(pendingFirstMessageProvider.notifier).state = null;
        _input.text = pending;
        await _send();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true, bool force = false}) {
    // Respect the user's reading position: while they're detached from the
    // bottom, streaming updates must not yank the view. `force` is for
    // user-initiated cases (sending a message, tapping the jump pill).
    if (!force && !_stickToBottom) return;
    if (force && !_stickToBottom) setState(() => _stickToBottom = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scrollController.hasClients) return;
      _activeAutoScrolls++;
      try {
        if (animate) {
          await _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent);
        }
      } finally {
        _activeAutoScrolls--;
      }
    });
  }

  bool _onScrollNotification(ScrollNotification n) {
    // A user-initiated drag ALWAYS wins over auto-scroll — release
    // stickiness immediately, even mid-animateTo. Before this check the
    // _activeAutoScrolls guard below swallowed the user's drag while a
    // streaming auto-scroll animation was in flight; with sub-250ms token
    // cadence an animation was effectively always active, so the list was
    // unscrollable for the entire response (reported post-launch).
    if (n is ScrollStartNotification && n.dragDetails != null) {
      if (_stickToBottom) setState(() => _stickToBottom = false);
      return false;
    }
    if (_activeAutoScrolls > 0) return false;
    if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      final near =
          n.metrics.maxScrollExtent - n.metrics.pixels <= _bottomSlackPx;
      if (near != _stickToBottom) {
        setState(() => _stickToBottom = near);
      }
    }
    return false;
  }

  /// Aggressively dismiss the keyboard. `FocusScope.of(ctx).unfocus()` alone
  /// proved unreliable on iOS — the OS would restore the text field as focused
  /// when the drawer or modal closed. Two-pronged: clear Flutter's primary
  /// focus AND tell the platform input plugin to hide.
  void _killKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    // Kimi-style unauth shell: the composer + drawer are freely browsable,
    // but hitting Send is where account creation becomes required (satisfies
    // Apple 5.1.1(v) — chat shell is not account-based, actually chatting
    // is). Bounce to the login screen with a friendly nudge; the user comes
    // back to this same chat after signing in.
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      HapticFeedback.mediumImpact();
      // A sheet, not a route. Pushing the login screen made it the root of the
      // stack (GoRouter drops imperative pushes across a redirect), so
      // hardware back from the sign-in wall left the APP — a new user who
      // typed a question and hesitated was ejected to their launcher. It also
      // dropped what they had typed.
      //
      // This screen stays mounted underneath with its composer intact, so once
      // there is an account we simply do what they already asked for.
      final signedIn = await showLoginSheet(context);
      if (!signedIn || !mounted) return;
      if (_input.text.trim().isNotEmpty) await _send();
      return;
    }
    final attachmentsNotifier =
        ref.read(pendingAttachmentsProvider(widget.chatId).notifier);
    final pending = ref.read(pendingAttachmentsProvider(widget.chatId));

    // Block sending if any attachment is still uploading
    if (pending.any((a) => a.uploading)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppL10n.of(context).uploadingFile),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (text.isEmpty && pending.isEmpty || _sending) return;

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    _input.clear();
    final apiAttachments = attachmentsNotifier.toApiAttachments();
    // Stash a server-url → local-path map BEFORE clearing the notifier.
    // The user just picked these files; we have them on disk. The
    // optimistic bubble's _UserAttachmentsStrip reads this map and
    // renders from the local file instead of round-tripping a server
    // proxy that doesn't accept our Bearer auth.
    final localPaths = {
      for (final a in pending)
        if (a.upload != null) a.upload!.url: a.localPath,
    };
    if (localPaths.isNotEmpty) {
      ref.read(localAttachmentPathsProvider.notifier).update(
            (m) => {...m, ...localPaths},
          );
    }
    attachmentsNotifier.clear();

    // sendMessage no longer throws on stream failure — failures show
    // up inline in the message list as a faded error bubble with retry.
    // We still catch unexpected exceptions just in case.
    try {
      await ref
          .read(chatDetailProvider(widget.chatId).notifier)
          .sendMessage(
            text,
            attachments:
                apiAttachments.isEmpty ? null : apiAttachments,
          );
    } catch (_) {
      // Unexpected — sendMessage handles its own errors inline now.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(chatDetailProvider(widget.chatId));
    final cs = Theme.of(context).colorScheme;

    // Which agent workspace this chat belongs to, or null for a plain chat.
    // Load-bearing in two places: the header stops offering Imagine, and the
    // empty state introduces the surface instead of greeting the user.
    final surface = ref.watch(agentSurfaceProvider(widget.chatId));

    // Auto-scroll when new tokens arrive (only while the user is at the
    // bottom — _scrollToBottom is stick-aware). Always jump, never animate:
    // a 250ms animateTo per token means an auto-scroll animation is active
    // for the whole stream, and its _activeAutoScrolls window used to eat
    // the user's own scroll gestures. Jumps are synchronous, so the guard
    // window is a single frame and the list stays fully draggable.
    ref.listen(chatDetailProvider(widget.chatId), (prev, next) {
      if (!next.hasValue) return;
      final isFirstData = prev?.hasValue != true;
      _scrollToBottom(animate: false, force: isFirstData);
    });

    // Reload when the network comes back.
    //
    // A chat opened while offline sits on "No internet connection" until the
    // user finds the Retry button — and it kept sitting there with the signal
    // bars full and the offline banner already gone, which reads as the app
    // being broken rather than the network having been. Measured twice on
    // device, 2026-08-05.
    //
    // Only from a failed state: a chat that loaded fine has nothing to
    // reload, and re-fetching under a live stream would be a way to lose a
    // reply mid-flight.
    ref.listen<bool>(isOfflineProvider, (wasOffline, isOffline) {
      if (wasOffline != true || isOffline) return;
      if (ref.read(chatDetailProvider(widget.chatId)).hasError) {
        ref.invalidate(chatDetailProvider(widget.chatId));
      }
    });

    // Stale-chat-403 recovery: the backend POST /chat/:id/complete
    // returns 403 when the chat doesn't belong to the current user
    // (most common cause: bootstrap routed to a previous-session chat
    // id from the cached chat list). On hit, create a fresh chat, push
    // the user's original text into pendingFirstMessageProvider, and
    // navigate. The new chat's detail screen reads pendingFirstMessage
    // on mount and auto-sends it — seamless from the user's POV.
    ref.listen<StaleSendRecovery?>(lastSendStaleChatErrorProvider,
        (_, next) async {
      if (next == null) return;
      ref.read(lastSendStaleChatErrorProvider.notifier).state = null;
      try {
        // Blacklist the chat that just 403'd on send so the shared
        // reuse path can never hand it straight back (an empty chat that
        // 403s on send would otherwise recover into itself forever).
        ref.read(blacklistedChatsProvider.notifier).add(widget.chatId);
        final fresh = await ref
            .read(chatListProvider.notifier)
            .reuseOrCreateEmptyChat();
        ref.read(pendingFirstMessageProvider.notifier).state =
            next.originalText;
        if (!context.mounted) return;
        context.goNamed(
          'chat-detail',
          pathParameters: {'id': fresh.id},
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't open a fresh chat. "
                '${userMessageFor(context, e)}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    // Paywall — any notifier (upload, tts, stt, model picker, …) can
    // request the paywall by writing into pendingPaywallTriggerProvider.
    // We surface a single contextualized sheet here so we never stack two
    // paywalls if multiple errors fire at once.
    ref.listen<PaywallTrigger?>(pendingPaywallTriggerProvider, (_, next) {
      if (next == null) return;
      ref.read(pendingPaywallTriggerProvider.notifier).state = null;
      showPaywall(context, reason: next.reason, details: next.details);
    });

    // Surface upload failures (network/413/5xx) as a SnackBar — the
    // small red chip overlay was getting missed, so users reported
    // "upload doesn't work" thinking nothing happened.
    ref.listen<String?>(lastUploadErrorProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $next'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      ref.read(lastUploadErrorProvider.notifier).state = null;
    });

    // Surface Continue/resume failures (MODEL_ACCESS_DENIED, timeout, etc.)
    // as a toast — original truncated bubble stays in place so the user
    // doesn't lose context.
    ref.listen<String?>(lastResumeErrorProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      ref.read(lastResumeErrorProvider.notifier).state = null;
    });

    return PopScope(
      // Sahachiel: allow leaving even mid-stream instead of trapping the user
      // behind the spinner — cancel the in-flight stream on the way out (the
      // provider also disposes, which breaks the stream loop).
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _sending) {
          ref
              .read(chatDetailProvider(widget.chatId).notifier)
              .stopStreaming();
        }
      },
      child: Scaffold(
          drawer: const AppDrawer(),
          // Content scrolls UNDER the bar and frosts out behind it (Grok /
          // iOS-26 material), instead of stopping at an opaque band.
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            // Plain page colour, NOT a glass band.
            //
            // `GlassSurface` fills with `surfaceContainer`, which is a
            // different tone from the page — so across the full width its
            // bottom edge read as a hairline rule under the app bar. There was
            // no border drawn; the line WAS the band. Painting the scaffold
            // colour keeps content from bleeding through under
            // `extendBodyBehindAppBar` while leaving no visible seam.
            flexibleSpace: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const SizedBox.expand(),
            ),
            leading: Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _killKeyboard();
                  Scaffold.of(ctx).openDrawer();
                },
              ),
            ),
            centerTitle: true,
            // Ask ↔ Imagine lives in the header (Grok pattern) — switching
            // between chatting and image generation is a high-frequency
            // move, and it used to cost a drawer trip. The model picker
            // moved down into the composer's control row, where it sits
            // next to the thing it actually affects.
            // Ask ↔ Imagine belongs to plain chat only. A Research or Code
            // session does not generate images, so offering the switch there
            // is generic chat chrome leaking into a surface that means
            // something specific — and tapping it would carry the user out of
            // the session they deliberately opened. Those show the surface's
            // own name instead, which is also the answer to "where am I".
            title: surface == null
                ? const AskImagineSwitch(mode: AskImagineMode.ask)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(surface.icon, size: 17, color: cs.primary),
                      const SizedBox(width: 7),
                      Text(
                        surface.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
            actions: [
              // + New chat — quick way to start a fresh conversation
              IconButton(
                tooltip: 'New chat',
                icon: Builder(
                  builder: (context) {
                    final cs = Theme.of(context).colorScheme;
                    return Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.outline),
                      ),
                      child: Icon(Icons.add_rounded,
                          size: 16, color: cs.onSurface),
                    );
                  },
                ),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  // If sitting in an empty chat, tell the user explicitly
                  // instead of silently no-op'ing. Silent no-op looked
                  // exactly like "+ doesn't work" in testing.
                  final current = detail.valueOrNull;
                  if (current != null && current.messages.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "You're already in a new chat — just type below to start.",
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  try {
                    // Reuse an existing empty chat (or create one) — the
                    // shared new-chat path; repeated + taps can't pile up
                    // blank chats.
                    final chat = await ref
                        .read(chatListProvider.notifier)
                        .reuseOrCreateEmptyChat();
                    if (context.mounted) {
                      context.pushReplacementNamed(
                        'chat-detail',
                        pathParameters: {'id': chat.id},
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Couldn't create chat. "
                              '${userMessageFor(context, e)}'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }
                },
              ),
              // 3-dots — Add to project / Star / Rename / Share / Delete
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  final d = detail.valueOrNull;
                  showChatOptionsMenu(
                    context: context,
                    ref: ref,
                    chatId: widget.chatId,
                    chatTitle: d?.chat.title ?? '',
                    currentVisibility: d?.chat.visibility ?? 'private',
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          // Grok-style floating composer: the message list fills the whole
          // body and the composer is layered ON TOP as frosted glass, so
          // content slides underneath and blurs out. The previous Column
          // layout ended the list at a hard edge, which visually guillotined
          // the last bubble against the composer's border.
          body: Stack(
            children: [
              Positioned.fill(
                // Tapping the message area dismisses the keyboard. Scoped
                // here (not on the whole body) so tapping the input bar
                // — send, attach, the TextField itself — doesn't trigger
                // the dismiss and break mid-typing UX.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _killKeyboard,
                  child: detail.when(
                  loading: () => const _MessagesShimmer(),
                  error: (e, _) {
                    // 403 on a chat detail almost always means the route
                    // carries a chat id that doesn't belong to the current
                    // user — usually a stale id from a prior OAuth session.
                    // Auto-bounce to the chat list with a toast so the user
                    // doesn't have to kill the app to recover (their
                    // workaround until now). Falls through to ErrorView for
                    // anything else.
                    if (e is ForbiddenException) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        // Blacklist this chat so the bootstrap doesn't
                        // pick it again — otherwise bootstrap → 403 →
                        // bounce → bootstrap → 403 → … infinite spinner
                        // (this was the post-delete loop the user hit).
                        ref
                            .read(blacklistedChatsProvider.notifier)
                            .add(widget.chatId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "This chat isn't available on your account. "
                              'Opening your chat list.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 3),
                          ),
                        );
                        // Send them to the welcome / chat list root.
                        context.goNamed('chats');
                      });
                      return const _MessagesShimmer();
                    }
                    // Keep clear of the composer. This body is a Stack and
                    // the composer is a sibling pinned to the bottom, so an
                    // error view left to centre itself in the FULL height puts
                    // its Retry button underneath it. Offline with the
                    // keyboard up, Retry landed exactly on the composer's
                    // "You're offline" row and neither could be read
                    // (device, 2026-08-05). The message list already reserves
                    // this same space.
                    return Padding(
                      padding: EdgeInsets.only(bottom: _composerHeight + 12),
                      child: ErrorView(
                        error: e,
                        onRetry: () => ref.refresh(
                            chatDetailProvider(widget.chatId).future),
                      ),
                    );
                  },
                  data: (d) {
                    if (d.messages.isEmpty && !_sending) {
                      void fill(String prompt) {
                        _input.text = prompt;
                        _input.selection =
                            TextSelection.collapsed(offset: prompt.length);
                        FocusScope.of(context).unfocus();
                      }

                      // A surface introduces itself. Opening a new Research
                      // session used to land on "Good afternoon — Brainstorm
                      // ideas", where nothing said Research and two of the
                      // three suggestions pointed back out to general chat.
                      if (surface != null) {
                        return SurfaceWelcome(
                            surface: surface, onPromptTap: fill);
                      }
                      return WelcomeHint(onPromptTap: fill);
                    }
                    // Show typing indicator while waiting for assistant's first token
                    final showTyping = _sending &&
                        (d.messages.isEmpty ||
                            d.messages.last.role == 'user');
                    // Agent tool activity renders as one trailing row under
                    // the conversation; it collapses to nothing when the
                    // agent hasn't used any tools.
                    final itemCount =
                        d.messages.length + 1 + (showTyping ? 1 : 0);

                    return NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            // Top pad clears the translucent app bar (the body
                            // extends behind it); bottom pad clears the
                            // floating composer so the newest bubble can
                            // scroll fully into view instead of parking
                            // behind the glass.
                            padding: EdgeInsets.fromLTRB(
                              16,
                              MediaQuery.of(context).padding.top +
                                  kToolbarHeight +
                                  12,
                              16,
                              _composerHeight + 12,
                            ),
                            itemCount: itemCount,
                            itemBuilder: (_, i) {
                              if (showTyping && i == itemCount - 1) {
                                return const TypingIndicator();
                              }
                              // Tool activity sits directly after the last
                              // message, before the typing indicator.
                              if (i == d.messages.length) {
                                return AgentActivityStrip(
                                    chatId: widget.chatId);
                              }
                              // Sahachiel: RepaintBoundary + stable key so a per-token
                              // rebuild of the streaming bubble doesn't repaint every
                              // other bubble on screen.
                              return RepaintBoundary(
                                key: ValueKey(d.messages[i].id),
                                child: MessageBubble(
                                  message: d.messages[i],
                                  chatId: widget.chatId,
                                  isLatest: i == d.messages.length - 1,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            right: 16,
                            bottom: _composerHeight + 12,
                            child: JumpToBottomPill(
                              visible: !_stickToBottom,
                              onTap: () =>
                                  _scrollToBottom(force: true),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ),
              ),
              // Floating glass composer + the fade that dissolves scrolling
              // text into the page just above it.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // RepaintBoundary: the composer's frosted glass is expensive
                // to paint, and without an isolation layer it repaints on
                // every streaming token update to the list behind it.
                child: RepaintBoundary(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ScrimFade(height: 32),
                      ChatComposer(
                        chatId: widget.chatId,
                        controller: _input,
                        sending: _sending,
                        onSend: _send,
                        onHeightChanged: (h) {
                          if (!mounted) return;
                          setState(() => _composerHeight = h);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }

}

class _MessagesShimmer extends StatelessWidget {
  const _MessagesShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CnShimmer(width: double.infinity, height: 60, radius: 14),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: CnShimmer(
              width: MediaQuery.of(context).size.width * 0.6,
              height: 44,
              radius: 14,
            ),
          ),
          const SizedBox(height: 16),
          const CnShimmer(width: double.infinity, height: 100, radius: 14),
        ],
      ),
    );
  }
}
