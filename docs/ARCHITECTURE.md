# Architecture

> Read this before adding a feature. The conventions are load-bearing — the
> codebase has grown to ~30k LoC and the patterns are the only thing keeping
> it navigable.

## Folder layout

```
lib/
├── app/
│   ├── app.dart                       MaterialApp.router root; reads themeMode
│   │                                  + locale + router providers
│   └── routes.dart                    GoRouter declarative tree (~25 named
│                                      routes); name-based navigation only
├── core/
│   ├── api/
│   │   ├── api_client.dart            Dio wrapper. NDJSON `stream()` returns
│   │   │                              Stream<String> of lines from /complete
│   │   └── interceptors/
│   │       ├── auth_interceptor.dart  Bearer attach + 401 single-flight refresh
│   │       │                          + onAccessTokenChanged hook into
│   │       │                          currentAccessTokenProvider
│   │       ├── error_interceptor.dart Map DioException → typed AppException
│   │       └── mobile_context_interceptor.dart  X-Client headers
│   ├── analytics/                     /analytics/events sink
│   ├── constants/
│   │   ├── api_constants.dart         All endpoint paths, baseUrl, webOrigin,
│   │   │                              resolveImageUrl() for host-relative URLs
│   │   └── app_constants.dart         Storage keys, page sizes, brand URLs
│   ├── errors/
│   │   ├── app_exception.dart         Unauthorized / Forbidden / NotFound /
│   │   │                              FeatureUnavailable / etc. — pattern-matched
│   │   └── error_messages.dart        userMessageFor(context, e) — localized
│   ├── layout/                        Responsive breakpoints, drawer width
│   ├── platform/
│   │   └── platform_flags.dart        showBilling, showUpgradeCta, isIOS/Android
│   └── storage/
│       └── secure_storage.dart        Keychain + currentAccessTokenProvider
│                                      (synchronous Bearer mirror for widgets)
├── features/
│   ├── auth/                          Google / Apple / email + JWT skeleton
│   ├── chat/                          The core — see "Chat feature" below
│   ├── images/                        Sync gen (Ideogram), gallery, save, delete
│   ├── voice/                         TTS playback + STT mic capture
│   ├── payment/                       Plans, paywall trigger, in-app browser
│   ├── projects/                      Code projects + bulk chat assign
│   ├── prompts/                       User custom prompts
│   ├── skills/                        Available skills
│   ├── memory/                        AI memory CRUD
│   ├── research/                      Streaming research queries
│   ├── discover/                      Published-content feed
│   ├── user/                          Profile, settings, sessions
│   ├── capabilities/                  Tier capability manifest
│   ├── splash/                        Letter-reveal animation
│   ├── design_lab/                    Internal preview ground (not in nav)
│   └── media/                         Images-only tab host
├── shared/
│   ├── theme/
│   │   ├── app_theme.dart             Dark + soft-gray light palettes
│   │   └── theme_mode_provider.dart   ThemeMode persisted in prefs
│   └── widgets/                       app_drawer, settings_sheet,
│                                      paywall_sheet, authed_network_image,
│                                      error_view, cn_shimmer, etc.
├── l10n/                              12 locales (en, ar, de, es, fr, hi, id,
│                                      it, ja, ko, nl, pl, pt, ru, th, tr, vi,
│                                      zh) — generated AppL10n
└── main.dart                          ProviderScope + native splash teardown
```

## State management

Riverpod 2.x. Three patterns cover ~95% of cases:

### 1. `AsyncNotifierProvider.autoDispose.family<X, ChatId>` for per-screen state

Used when state is keyed by an ID and shouldn't outlive the screen.

```dart
final chatDetailProvider = AsyncNotifierProvider.autoDispose.family<
    ChatDetailNotifier,
    ({ChatModel chat, List<MessageModel> messages}),
    String>(ChatDetailNotifier.new);

class ChatDetailNotifier extends AutoDisposeFamilyAsyncNotifier<
    ({ChatModel chat, List<MessageModel> messages}), String> {
  @override
  Future<...> build(String chatId) async {
    return ref.read(chatRepositoryProvider).getChatWithMessages(chatId);
  }

  Future<void> sendMessage(String text, {...}) async { /* mutates state= */ }
}
```

Notes:
- `arg` is the chatId inside the notifier.
- `autoDispose` means leaving the chat detail screen tears it down. Re-entering
  re-fetches (cheap because we paginate).
- Mutations call `state = AsyncData(newValue)` — never `state = ...` inside a
  Future that races other awaits unless you've captured the current value first.

### 2. `NotifierProvider<X, Y>` for app-wide collections

Used for the chat list, image list, drawer selection sets — anything that should
survive navigation.

```dart
final chatListProvider =
    AsyncNotifierProvider<ChatListNotifier, List<ChatModel>>(ChatListNotifier.new);

class ChatListNotifier extends AsyncNotifier<List<ChatModel>> {
  @override
  Future<List<ChatModel>> build() async {
    // Watch authProvider's user id so login/logout invalidates this list
    // — otherwise the previous user's chats persist across account switches.
    ref.watch(authProvider.select((v) => v.valueOrNull?.id));
    return _fetch();
  }
}
```

### 3. `StateProvider<X>` for transient flags + "trigger" payloads

The codebase prefers small `StateProvider`s over global event buses for
cross-feature signaling. Producer writes a non-null value, the screen-level
listener reads it, fires UI, then sets it back to null.

Examples:
- `pendingPaywallTriggerProvider` — upload/TTS/chat notifiers write a
  `PaywallTrigger`; chat detail screen listens and surfaces the sheet.
- `lastSendStaleChatErrorProvider` — sendMessage writes on 403; screen listens,
  creates a fresh chat, replays the message via `pendingFirstMessageProvider`.
- `lastResumeErrorProvider` — resume failures become toasts.
- `currentAccessTokenProvider` — synchronous Bearer for `AuthedNetworkImage`.

## Chat feature — the big one

This module is ~3k LoC and has the most subtle invariants. Read carefully before
touching.

### Providers

| Provider | Scope | Purpose |
|---|---|---|
| `chatListProvider` | App | Paginated chat list; rebuilds on auth change |
| `chatDetailProvider(id)` | Per chat | Messages + chat metadata; autoDispose |
| `pendingFirstMessageProvider` | App | One-shot text typed on a welcome / fresh-chat screen, auto-sent on chat detail mount |
| `pendingAttachmentsProvider(chatId)` | Per chat | Upload-state-tracked attachments |
| `truncatedMessagesProvider` | App | Set of message IDs whose `done.truncated == true` (drives Continue pill) |
| `streamRunningProvider` | App | True while any stream is in flight; disables Continue / send during it |
| `activeWebSearchProvider` | App | Current web-search badge state for the typing indicator |
| `lastTurnUsageProvider` | App | Most recent token usage from `usage` event |
| `lastSendStaleChatErrorProvider` | App | StaleSendRecovery payload — drives create-fresh-chat + replay flow |
| `lastResumeErrorProvider` | App | Resume failure message — drives toast |
| `blacklistedChatsProvider` | App | Chat IDs that 403'd this session; ChatBootstrapScreen skips them |
| `selectedChatsProvider` | App | Drawer multi-select set (toggle via long-press) |
| `webSearchToggleProvider(chatId)` | Per chat | "🌐 Search" pill state; sets `forceWebSearch: true` on next send |

### Streaming lifecycle

```
sendMessage(text)
  ├── Optimistically add user message to state
  ├── Build temp assistant id "streaming_<ts>"
  ├── Open repo.streamCompletion(..., forceWebSearch: toggle)
  │   └── Returns Stream<StreamEvent>
  ├── await for each event with 90s timeout:
  │     start(messageId, model, mode)  → swap temp id → server id
  │     status(web-searching / -searched / -no-results)
  │                                   → activeWebSearchProvider
  │     token(content)                 → accumulate into assistant bubble
  │     usage(...)                     → lastTurnUsageProvider
  │     done(messageId, truncated)     → mark in truncatedMessagesProvider
  │                                       if truncated; invalidate chatList
  │     error(code, msg)               → if CONTEXT_EXCEEDED, suggest fresh
  │                                       chat; else fall through to inline
  │                                       error bubble (with retry)
  ├── on ForbiddenException → __STALE_CHAT_403__ sentinel
  │       → lastSendStaleChatErrorProvider triggers screen to create fresh
  │         chat + replay
  └── finally → clear streamRunning + activeWebSearch
```

### Continue / resume

If the model hits `max_tokens`, the server emits `done.truncated = true`. The
notifier marks the message in `truncatedMessagesProvider`. The UI surfaces a
"Continue" pill on the bubble. Tapping it:

```
resumeMessage(messageId)
  ├── Clear truncatedMessagesProvider for this id
  ├── repo.streamResume(chatId, messageId)
  ├── For each token, append to the EXISTING bubble (no new bubble)
  ├── On done.truncated again, re-add to truncatedMessagesProvider
  └── On error, surface lastResumeErrorProvider (toast)
```

Server route: `POST /chat/<id>/complete/resume` with `{messageId}`. Server
re-feeds the conversation + the partial assistant message + a "do not repeat,
do not preamble, continue from the next character" instruction.

### 403 recovery (stale-chat protection)

Two layers, because two different things can 403:

1. **chatDetailProvider 403** (e.g. chat was deleted server-side, or stale id
   from prior OAuth session): `chat_detail_screen.dart`'s error branch adds the
   id to `blacklistedChatsProvider` and navigates to `/chats`.
   `ChatBootstrapScreen` then picks `chats.firstWhere(!blocked)` — won't loop
   on the same blacklisted chat.

2. **sendMessage 403** (chat doesn't accept this user): notifier swaps the
   sentinel `__STALE_CHAT_403__` into the error path. The screen creates a
   fresh chat via `chatListProvider.createChat()`, stuffs the user's original
   text into `pendingFirstMessageProvider`, and navigates. New chat auto-sends
   on mount. User sees a single seamless transition.

### Multi-select (drawer chats + image gallery)

Both follow the same pattern:

- A `selectedXProvider` (Set<String>).
- Long-press a list/grid item → `toggle(id)`. Empty set → normal mode; non-empty
  → selection mode.
- Selection mode swaps the chrome (drawer header / gallery AppBar) with a
  contextual action bar showing count + actions (Delete, Add to project, etc.).
- Tap toggles in selection mode; the regular onTap (open detail) only fires
  in normal mode.
- Selection state is independent of which screen is active — flipping the drawer
  doesn't lose it.

## Auth

`AuthRepository` owns three things:

1. **Token persistence**: writes to `flutter_secure_storage` AND to
   `currentAccessTokenProvider` (synchronous mirror for image-loading widgets).
2. **OAuth race-handling**: `_fetchMeWithFallback()` retries `/auth/me` 5×
   (~3s total) after a fresh OAuth, then falls back to a JWT-decoded skeleton
   user if the race never resolves. A background refresh fires 4s later to fill
   in the real profile.
3. **Transparent refresh**: the `AuthInterceptor` catches 401s, takes a
   single-flight lock on the refresh future (so concurrent 401s don't fire
   N refresh calls), refreshes via `/auth/refresh`, updates the token mirror
   via `onAccessTokenChanged`, and retries the original request once.

## Image flow

1. `POST /images/generate` is **synchronous** as of the backend API (Ideogram 4 on
   Box A returns bytes in ~15s). No polling.
2. Response is `{success, images: [{url}], usage}`. `url` is host-relative
   `/api/images/<uuid>/view`. `ApiConstants.resolveImageUrl()` prepends
   `webOrigin` so `CachedNetworkImage` can fetch it.
3. Image view endpoint requires Bearer — use `AuthedNetworkImage`, NOT plain
   `CachedNetworkImage`, anywhere a generated-image URL is rendered. The wrapper
   reads `currentAccessTokenProvider` and attaches `Authorization: Bearer ...`
   via `httpHeaders`.
4. Optimistic prepend: `imagesListProvider.prepend(freshImage)` puts the new
   image at the head of the gallery before the next list refetch.
5. Save to Photos via `ImageDownloader` — auth-fetches the bytes, hands them
   to `gal`. Custom `PhotosPermissionDeniedException` for the "open Settings"
   hint.
6. Delete: `DELETE /api/mobile/v1/images/<uuid>` — mobile-namespaced as of
   the backend API. Single + bulk both go through `ImagesListNotifier.deleteOne/Many`.

## Paywall pattern

One reusable sheet, contextualized by `PaywallReason`. Any notifier that hits a
tier-gated 403 writes to `pendingPaywallTriggerProvider`. The chat detail screen
(and any other screen that wants to surface it — image_generate_screen does too)
adds a `ref.listen` that calls `showPaywall(context, reason: ...)`.

```
[upload notifier] → caught ForbiddenException(TIER_REQUIRED)
                  → state = [...state without failed chip]
                  → ref.read(pendingPaywallTriggerProvider.notifier).state
                      = PaywallTrigger(reason: PaywallReason.fileUpload)

[screen] watches pendingPaywallTriggerProvider:
            on non-null → null it out, call showPaywall(...)
            showPaywall renders bottom sheet
              CTA: "Upgrade" → PaymentRepository.openUpgrade()
                            → SFSafariViewController on iOS
                              Chrome Custom Tabs on Android
```

`PaywallReason` enum: `fileUpload`, `fileSizeLimit`, `premiumModel`,
`insufficientUnits`, `imageGenCap`, `webSearchRateLimit`, `voiceListen`,
`voiceSpeak`, `generic`. Each swaps the headline + the highlighted benefit row.

## Network layer

`ApiClient` is the only Dio instance. All repos go through it.

- `baseUrl` defaults to `https://cyberneurova.ai/api/mobile/v1`, overridable
  with `--dart-define=API_BASE_URL=...`.
- For host-relative paths (like `/api/images/<uuid>/view` which is NOT under
  `/api/mobile/v1`), use `ApiConstants.webOrigin` + the path.
- For binary downloads (image save-to-Photos), construct a one-off Dio (not the
  ApiClient instance) to skip JSON content-type defaults and the 401 refresh
  interceptor. See `ImageDownloader`.

## Theme

`AppTheme.dark` is the canonical palette (matches chat-app's `globals.css`
`.dark` block — OKLCH → sRGB). `AppTheme.light` is a soft warm gray palette
(NOT pure white — user feedback was that pure white was harsh; we use
#ECECEE-ish bg with #F4F4F6 surfaces).

`themeModeProvider` is a `Notifier<ThemeMode>` persisted to SharedPreferences.
Default: `ThemeMode.system`.

**Don't hardcode `AppTheme.background`, `AppTheme.foreground`, `Colors.white`
etc. in new code.** Use `Theme.of(context).colorScheme` (`onSurface`,
`surfaceContainer`, `primary`, `outline`, `onSurfaceVariant`). The hardcoded
constants only render correctly in dark mode — a chunk of the codebase still
violates this and needs a sweep.

## Localization

12 + variants — see `l10n/`. Generated `AppL10n` via `flutter_localizations`.
Use `AppL10n.of(context).<key>` not hardcoded English. Server errors get a
localized lookup via `userMessageFor(context, e)`.

## Build + ship

- `flutter build ipa --release` → `build/ios/ipa/CyberNeurova.ipa`
- `xcrun altool --upload-app --type ios -f <ipa> --apiKey <id> --apiIssuer <id>`
  uploads to the store (~3 min for upload + 15-30 min for Apple processing).
- Build number lives in `pubspec.yaml` `version:` line as `1.0.0+N`. Bump `+N`
  for every the store upload; Apple rejects duplicates.
- Avoid `flutter run` for on-device installs from CI / agentic contexts — it
  attaches a foreground process and freezes the terminal. Use `flutter install`
  or `xcrun devicectl device install app`.

## Things that are intentionally NOT here

- **StoreKit / Google Play Billing** — we use the in-app browser pattern for
  checkout. Can be added if Apple ever rejects the current approach (~1 day).
- **Custom backend / parallel API** — every persistent feature goes through
  the backend `/api/mobile/v1` endpoints. Don't add a sidecar.
- **WebSocket / Server-Sent Events** — server uses chunked NDJSON for chat
  streams. WS only for the voice orchestrator (out of scope for this app).
- **Sentry / Datadog** — analytics events go to `/analytics/events` on the
  the backend API. No third-party SDK.
- **Heavy navigation libraries** — go_router is the only routing dep. No
  auto-route, beamer, etc.
