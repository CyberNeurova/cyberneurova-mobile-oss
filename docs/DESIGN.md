# CyberNeurova Mobile — Design Reference

A briefing for designers joining the project. It describes what the app is,
how it is built, how navigation and screens actually work, and where the
seams are. Code samples are included where the shape of the code constrains
the design — those are the places where "just make it look like X" will run
into something real.

Last updated: 2026-08-02, against build 41 (`1.0.1+41`).

---

## 1. What the app is

CyberNeurova is an AI assistant. The user chats with models we host
ourselves; there is no third-party AI provider behind it. On top of chat sit
image generation, a research workspace, and a code workspace.

It is live on the iOS App Store and in the store. Android exists in the same
codebase and is polished by the desktop app. **Every design decision has to
work on both platforms** — we ship one Flutter codebase, not two native apps.

Four paid tiers (Starter $17.99, Premium $39.99, Pro, Pro Max) sold through
StoreKit on iOS. There is a free tier with real capability, not a trial.

### The most important constraint

The app is **Flutter**, not native Swift/Kotlin. Some architecture docs
circulating internally assume native — they are wrong about that, and the
assumption changes real decisions (terminal renderer, FFI bindings, how
platform channels are used). Confirm the stack before designing anything
that depends on it.

---

## 2. Stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.44+, Dart 3.3+ |
| State | Riverpod (`AsyncNotifier`, `Notifier`, `StateProvider`) |
| Navigation | `go_router` — declarative routes, named navigation |
| Network | Dio, with interceptors for auth and error normalisation |
| Local storage | `shared_preferences` (prefs), `flutter_secure_storage` (tokens) |
| Markdown | `flutter_markdown` |
| Payments | `in_app_purchase` (StoreKit 2 / Play Billing) |
| Localisation | ARB files, 20 locales |

Directory shape:

```
lib/
├── app/                    routes.dart — every route in one file
├── core/                   api client, constants, errors, platform flags
├── features/<name>/
│   ├── data/               models (freezed), repositories
│   └── presentation/
│       ├── providers/      Riverpod providers
│       ├── screens/        full pages
│       └── widgets/        feature-local widgets
├── l10n/                   ARB translations
└── shared/
    ├── theme/              app_theme.dart — all design tokens
    └── widgets/            cross-feature widgets
```

Features: `agents`, `auth`, `capabilities`, `chat`, `code`, `discover`,
`images`, `legal`, `media`, `memory`, `payment`, `projects`, `prompts`,
`research`, `splash`, `user`, `video`, `voice`. 34 screens.

---

## 3. Design tokens

All in `lib/shared/theme/app_theme.dart`. **Never hardcode a colour in a
widget** — read it from `Theme.of(context).colorScheme`, so light mode and
dark mode both work without a second pass.

### Colour (dark, the primary palette)

| Token | Hex | Use |
|---|---|---|
| `background` | `#0B1221` | Page background — deep navy, not black |
| `surface` | `#121C30` | Cards, sheets |
| `surfaceElevated` | `#1B2742` | Raised surfaces, user message bubble |
| `border` | `#253250` | Hairlines, outlines |
| `foreground` | `#EAF1FC` | Primary text |
| `muted` | `#94A3C2` | Secondary text |
| `dim` | `#63718F` | Tertiary text, disabled |
| `accent` | `#2FE0C7` | Brand teal — primary actions, links, focus |
| `onAccent` | `#052B25` | Text on accent (dark, not white) |
| `accentAlt` | `#8B6FE6` | Purple, used sparingly |
| `error` | `#FF6B6B` | Destructive, errors |

Light mode is a full second palette in the same file. **Contrast differs
enough between the two that a value tuned for dark often disappears in
light.** The codebase already carries per-brightness overrides in several
places — for example, a hairline border at 0.35 alpha reads fine on navy and
vanishes on the light page, so the light variant uses full alpha:

```dart
double get _outlineAlpha =>
    Theme.of(context).brightness == Brightness.light ? 1.0 : 0.35;
```

If you specify a subtle treatment, specify it twice.

### Radius

| Token | px | Use |
|---|---|---|
| `radiusXs` | 8 | Badges, tags, chip interiors |
| `radiusSm` | 12 | Small controls, snackbars |
| `radiusMd` | 14 | Cards, buttons, inputs, menus |
| `radiusLg` | 18 | Large cards, dialogs, user bubble |
| `radiusXl` | 24 | Composer pill, bottom sheets |

### Spacing and touch targets

Spacing runs on a 4/8 grid. **Every interactive element must be at least
44×44pt** — that is an Apple HIG requirement, and reviewers do check. The
codebase enforces it with `minimumSize: Size(44, 44)` on text buttons and
padding that pushes rows past 48px.

### Type

Body is the system font. Display/brand text uses a serif, via
`AppTheme.serifDisplay(size:, color:)`. Note the `color:` parameter is not
optional in practice — the default is the dark palette's near-white, so
omitting it makes the text invisible in light mode.

---

## 4. Navigation

One file: `lib/app/routes.dart`. Every route is named; navigation is by name,
never by raw path string.

### The two navigation verbs

This distinction matters more than it looks, and getting it wrong is the most
common navigation bug in the app.

```dart
context.goNamed('chats');        // REPLACE — no back stack growth
context.pushNamed('settings');   // PUSH — adds to back stack, back returns
```

Use `go` for sibling surfaces the user swaps between (Ask ↔ Imagine, picking
a chat from the drawer). Use `push` for drilling into detail (a project, a
setting, a chat from search).

Getting this backwards produces the "pressing back twelve times walks through
every chat I opened" bug.

### Transitions

Two custom builders in `routes.dart`:

- `_fade` — splash, auth, the chat root. Calm entrances.
- `_slideRight` — everything pushed. Horizontal slide, reads as depth.

Imagine deliberately uses `_slideRight` even though it is a sibling of Ask,
so the pair reads as one surface swapping sideways.

### Route map

```
/splash                        → SplashScreen (entry point)
/auth/login | register | forgot-password
/consent                       → first-launch data disclosure

ShellRoute (wraps everything below in an offline banner)
  /chats                       → ChatBootstrapScreen  [Ask]
  /chats/:id                   → ChatDetailScreen
  /image/generate              → ImageGenerateScreen  [Imagine]
  /image/:id                   → ImageDetailScreen
  /media                       → MediaScreen
  /agents                      → AgentsScreen (hub)
  /research                    → ResearchListScreen
  /research/:id                → ResearchDetailScreen
  /code                        → CodeSessionsScreen
  /chat-search                 → ChatSearchScreen
  /archived-chats              → ArchivedChatsScreen
  /settings                    → SettingsScreen
  /profile-projects            → ProjectsScreen
  /profile-projects/:id        → ProjectDetailScreen
  /billing-plans               → PlansScreen
  … plus profile sub-screens
```

### Auth gating

A redirect in the router. Three routes are public so an unsigned-in user can
browse the app — this is not a preference, it is Apple guideline 5.1.1(v),
which forbids gating non-account-based features behind a login wall:

```dart
const publicUnauthRoutes = <String>{'/chats', '/consent', '/settings'};
if (!isLoggedIn && !isAuthRoute && !isPublic) return '/auth/login';
```

The unauthenticated user sees the full chat shell — composer, drawer,
settings. **Login is only required at the moment they press Send.** Kimi,
You.com and Perplexity all ship this shape. Do not design a flow that puts a
wall earlier than Send.

---

## 5. App structure — how a user moves through it

```
Splash (brand animation, at most 2×/day)
  │
  ├─ first launch → Consent screen → I Agree
  │
  ▼
Ask  ⇄  Imagine          ← header segmented switch, one tap apart
  │
  └─ hamburger → Drawer
        ├─ Projects → a project → its chats
        ├─ Agents   → Research → a session
        │           → Code     → a session
        ├─ Recents (chat history, swipe/long-press to manage)
        ├─ Archived (N)
        └─ bottom bar: Search · Settings · New chat
```

### The header

```
[☰]        [ Ask | Imagine ]        [+]  [⋮]
```

Ask and Imagine are the two primary surfaces. The switch is persistent on
both, because switching between chatting and generating images is a
high-frequency move that previously cost a drawer trip. This is why the
drawer no longer lists Media.

The model picker used to sit in this slot; it moved down into the composer,
next to the thing it affects.

### The composer (Grok-style frosted glass)

The single most-touched surface in the app. It **floats over** the message
list rather than sitting below it — messages scroll underneath and blur out.

Layout when idle:

```
┌───────────────────────────────────────┐
│  Message CyberNeurova…                │   ← text field, 1–6 lines
│                                       │
│  [+]  [Tiny Neurova ⌄]        [🎤]   │   ← controls row
└───────────────────────────────────────┘
```

It morphs between four states in one clipped container: idle, holding-to-
record, locked recording, and transcribing. Everything lives inside a single
rounded box so the voice waveform can never spill outside it.

Why it floats: laid out in a `Column` below the list, the list ended at a
hard edge and the last message was visually guillotined by the composer's
border. Floating it, plus a gradient scrim above, makes text dissolve into
the page instead of colliding with a wall.

The implementation detail that constrains design here: **the message list's
bottom padding tracks the composer's live height.** The composer measures
itself after layout and reports up:

```dart
// chat_composer.dart
void _reportHeight() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if ((h - _lastReportedHeight).abs() < 0.5) return;
    _lastReportedHeight = h;
    widget.onHeightChanged!(h);
  });
}
```

So the composer can grow freely (multi-line, attachment strip, voice bar) and
the newest message still scrolls clear of it. Any redesign that changes the
composer's height dynamically gets this for free — but a design that puts
content *outside* the measured container will be hidden behind glass.

---

## 6. How chat is displayed

### Message rendering

Assistant replies are **plain text on the page background**, full width, no
bubble. User messages are right-aligned in a soft rounded rect with a subtle
tail. This asymmetry is deliberate: the assistant's output is the content,
the user's message is an annotation on it.

An assistant message is not rendered as one blob. It is **segmented** first,
then each segment gets its own renderer:

```dart
for (final s in segments)
  if (s.isCode)             CodeTeaser(code: s.code!, language: s.language)
  else if (s.isMath)        _MathBlock(latex: s.math!)
  else if (s.isGeneratedImage) _GeneratedImageBlock(rawUrl: ...)
  else if (s.isToolRun)     ToolRunCard(...)
  else                      MarkdownBody(data: s.text, styleSheet: sheet)
```

Segments are parsed out of the raw text by markers:

| Marker | Renders as |
|---|---|
| ` ```lang … ``` ` | Collapsed code teaser, tap to open full panel |
| `$$latex$$` | Rendered math block |
| `[GENERATED_IMAGE:/api/images/<uuid>/view]` | Inline image |
| `[TOOL_RUN:{json}]` | Tool-run card with steps |

Segment parsing results are cached by text content, bounded to 128 entries.

### How code is displayed — the current state

This is an area you should expect to redesign.

Code blocks render as a **`CodeTeaser`**: a collapsed preview showing the
language and the first few lines. Tapping opens a full `CodePanel` with
syntax highlighting (`flutter_highlight`) and a copy button.

What does **not** exist today:

- No file tree. A reply containing five files renders five separate,
  unrelated code blocks with no sense that they belong to one project.
- No preview or run. If the model writes an HTML game, you can read it and
  copy it. You cannot play it.
- No persistence. Code blocks live in the chat transcript and nowhere else.
- No diffs, no change history, no working directory.

The Code workspace (Agents → Code) currently lists sessions and nothing more.
A session is an ordinary chat tagged `section: 'code'` — it inherits
streaming, attachments and history for free, but has no code-specific
behaviour beyond the rendering above.

**Constraint for whoever designs the preview feature:** Apple guideline 2.5.2
forbids downloading and executing code. Running HTML/CSS/JS inside a
`WKWebView` is explicitly permitted — that is how Replit and CodeSandbox
ship on iOS. So a web target can be previewed and played; a Rust or Python
project can only be displayed, not run, unless execution happens server-side.
Design the preview affordance so it is honest about which targets are
runnable.

### Streaming

Tokens arrive over a stream and are appended to the assistant message. Two
performance constraints shape what is possible visually:

1. **Tokens are batched, not applied individually.** At 50–100 tokens/sec,
   updating state per token re-renders and re-parses the whole growing
   message and starves the UI thread. Updates flush on a timer that backs off
   as the message grows — 50ms under 2000 chars, 80ms under 6000, 120ms
   beyond. It still reads as continuous typing.

2. **Selectable text is disabled while streaming.** `MarkdownBody(selectable:
   true)` builds a full `SelectableText` span tree, which is the dominant
   per-frame cost. Selection returns when the reply finishes.

Practical implication: **any per-token animation is expensive.** A cursor
that blinks per token, or a character-by-character reveal, will cost frames
on long replies. Animate at the message level, not the token level.

### Auto-scroll

While the user is at the bottom, new tokens keep the view pinned. Scrolling
up detaches — streaming updates then never yank the view. Returning to within
80px of the bottom re-attaches, as does tapping the jump-to-bottom pill.

A user drag always wins over auto-scroll, unconditionally. This was a real
bug: auto-scroll ran a 250ms animation per update and suppressed scroll
handling for its duration, so with tokens arriving faster than 250ms the
suppression was permanently on and the list was unscrollable for the entire
response.

---

## 7. The drawer

Frosted navy glass, rounded on the right edge, full-height.

```
┌──────────────────────────┐
│  CyberNeurova            │  serif wordmark
│  ◯ Kelvin   [Pro]        │  identity block → settings
├──────────────────────────┤
│  📁 Projects             │
│  ⬡  Agents               │  → Research · Code
├──────────────────────────┤
│  RECENTS                 │
│  Chat title      2h ago  │  swipe → Archive · Delete
│  …                       │  long-press → multi-select
│  ▸ Archived (3)          │
├──────────────────────────┤
│ [ 🔍 Search ] [⚙] [✎]   │  floating pill bar
└──────────────────────────┘
```

Destinations sit **above** the chat history, matching the common pattern in
modern chat apps. Two destinations only; the sidebar is deliberately short.

### Selection mode

Long-press any chat row anywhere in the app to enter it. Once active, a plain
tap toggles instead of navigating — Gmail/Photos semantics. The action bar
replaces the drawer header, and the bottom bar hides, so the mode reads as
exclusive.

Actions: Cancel · Select all · Archive/Unarchive · Add to project · Delete.

The same bar is shared by the drawer, the search screen, the archived screen
and the code screen, so the interaction is identical wherever chats are
listed.

**Archiving is currently device-local** (`shared_preferences`) because the
backend has no archive endpoint. It does not sync across devices. The
provider is written as a drop-in cache over a future server field.

---

## 8. Screen patterns to reuse

### Full-page list screen

Serif title centred, back or menu at left, list below. Used by Research,
Agents, Code.

### Grouped card settings list

Rows inside a bordered rounded card, hairline separators between. Used by
Settings and Projects. Each row: leading icon, label, optional trailing
value, chevron.

### Bottom sheet

`radiusXl` top corners, drag handle, content, primary action. Used for
paywall, model picker, project editor, options menus.

### Async state

Every screen that loads data handles four states. Loading is a **shimmer that
mirrors the real layout**, never a bare spinner:

```dart
projects.when(
  loading: () => const _ProjectsShimmer(),
  error:   (e, _) => ErrorView(error: e, onRetry: ...),
  data:    (list) => list.isEmpty ? _EmptyState() : _List(list),
)
```

Empty states get an icon, a heading, a sentence explaining how to get
content, and usually a CTA.

---

## 9. Platform rules that constrain design

These come from App Store review. We have been rejected six times; each of
these is a scar.

| Rule | What it means for design |
|---|---|
| **3.1.1** | On iOS, subscriptions must go through StoreKit only. No web checkout, no card/crypto option, not even as a fallback. |
| **3.1.2(c)** | Every paywall shows: tier name, duration, price, renewal disclosure text, and working links to Terms of Use and Privacy Policy. |
| **5.1.1(v)** | Features that are not account-based cannot sit behind a login wall. |
| **5.1.1(i)** | First launch discloses what data is sent, to whom, and gets explicit consent before anything is transmitted. |
| **2.5.2** | No downloading and executing code. Web code in a `WKWebView` is fine. |
| **2.1(a)** | Everything visible must work. A dead button is a rejection. |
| Background | iOS suspends the app within ~30s of backgrounding. Long-running work must live server-side, with a Live Activity for progress. |

The paywall legal footer is not optional decoration:

> Subscriptions auto-renew monthly at the price shown until cancelled at
> least 24 hours before the end of the current period. Payment is charged to
> your Apple ID at confirmation of purchase.
>
> Terms of Use (EULA) · Privacy Policy

It must appear on the Plans screen **and** the paywall sheet.

---

## 10. Android

Same Flutter codebase, polished by the desktop app. Design once, but check:

- Back gesture and the system back button both need to work.
- Material ripples vs iOS's opacity press states — Flutter handles most of
  this, but custom widgets need both.
- Android keeps the web checkout path (Play Billing products do not exist
  yet), so payment screens differ by platform. Gated in one place:
  `PlatformFlags.showBilling`.
- Safe areas differ. Do not hardcode inset values.

---

## 11. Where the current design is weakest

Honest list, roughly in order of how much it hurts.

1. **Code display.** Isolated blocks with no project structure, no preview,
   no persistence. The biggest gap between what the app implies and what it
   does.
2. **Agents feels like a folder, not an agent.** Sending a message in a Code
   session behaves exactly like a normal chat — no visible plan, no tool
   cards, no sense of an agent working. The name promises something the
   behaviour does not deliver.
3. **Research.** Missing icons, thin session rows, no management.
4. **Projects.** Only just gained a detail view. No sense of a project as a
   workspace with state.
5. **Long-conversation performance.** Better after batching, but a very long
   transcript still costs.
6. **Light mode.** Under-tested relative to dark. Several surfaces were tuned
   against dark only — the glass composer and the Ask/Imagine switch most
   recently.

---

## 12. Working agreements

- Read tokens from `Theme.of(context).colorScheme`; never hardcode colour.
- Specify light and dark, or the design ships broken in one of them.
- ≥44pt touch targets, always.
- New user-facing strings go in the ARB files (20 locales). The codebase does
  carry hardcoded strings for section labels — match the surrounding
  convention rather than mixing styles within one screen.
- Every async surface needs loading, error, empty and data states specified.
- Animate at the message or screen level, not per token.
- If a design needs backend that does not exist, say so in the spec. Several
  features are currently blocked on exactly that, and it is better surfaced
  early than discovered at implementation.
