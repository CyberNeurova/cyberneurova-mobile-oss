# Setup Guide

## 1. Install Flutter

```bash
# macOS via Homebrew
brew install --cask flutter

# Verify (should show no critical issues)
flutter doctor
```

Resolve anything `flutter doctor` flags — especially Xcode licenses and Android SDK.

## 2. Open the project

```bash
cd cyberneurova/cyberneurova_mobile
```

## 3. Environment variables

```bash
cp .env.example .env
# Edit .env:
#   API_BASE_URL=https://cyberneurova.ai/api/mobile/v1
#   For local dev: API_BASE_URL=http://localhost:3000/api/mobile/v1
```

## 4. Install dependencies

```bash
flutter pub get
```

## 5. Generate code (models + providers)

```bash
dart run build_runner build --delete-conflicting-outputs
# Watch mode during development:
dart run build_runner watch --delete-conflicting-outputs
```

## 6. Add fonts

Download [Inter](https://rsms.me/inter/) and place in `assets/fonts/`:
- `Inter-Regular.ttf`
- `Inter-Medium.ttf`
- `Inter-SemiBold.ttf`
- `Inter-Bold.ttf`

## 7. Set up the app icon

See [docs/ICON_SETUP.md](ICON_SETUP.md) for full instructions.

Short version:
1. Place `assets/icons/app_icon.png` (1024×1024 square CN logo, `#0F0F14` background)
2. Place `assets/icons/app_icon_foreground.png` (1024×1024, transparent background)
3. Place `assets/icons/app_icon_mono.png` (512×512 white-on-transparent CN mono)

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## 8. Initialize native platform folders

If `android/` and `ios/` directories don't exist yet:
```bash
flutter create --platforms=android,ios .
```

## 9. Run

```bash
# iOS Simulator
flutter run --dart-define-from-file=.env

# Android Emulator
flutter run -d emulator-5554 --dart-define-from-file=.env

# List available devices
flutter devices
```

### Dev auth bypass (UI development)

```bash
flutter run -d emulator-5554 --dart-define=DEV_AUTH_BYPASS=true
```

Boots straight into the app as a fake pro-tier user (`dev@cyberneurova.local`)
so every authed screen — drawer, settings, paywall, projects — is reachable
without an account. API calls still hit the real backend and fail; this is for
developing and reviewing UI only. Ignored in release builds (`kDebugMode` gate
in `auth_provider.dart`).

Payment surfaces are sandboxed too: the Plans screen gets canned monthly plans
(`billing_provider.dart`) and a canned multi-source `/iap/status` (pro via
Apple + premium via card, `IapRepository.getStatus`), so the current-plan card
and the "All subscriptions" list render with no network. The store itself is
queried for real and comes back unavailable on emulators, which exercises the
web-checkout fallback path.

## 10. Release builds

```bash
# Android APK
flutter build apk --release --dart-define-from-file=.env

# Android App Bundle (Play Store)
flutter build appbundle --release --dart-define-from-file=.env

# iOS
flutter build ios --release --dart-define-from-file=.env
```

---

## Local dev against cyberneurova_chat

1. Start chat app: `cd ../cyberneurova_chat && npm run dev`
2. Set `.env`:
   - iOS Simulator: `API_BASE_URL=http://localhost:3000/api/mobile/v1`
   - Android Emulator: `API_BASE_URL=http://10.0.2.2:3000/api/mobile/v1`

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `flutter pub get` fails | Check Flutter SDK ≥ 3.22 is on `$PATH` |
| Build runner errors | `rm -rf .dart_tool/build` then re-run |
| Auth 401 loop | Clear app data, log in fresh |
| Streaming hangs | Check `receiveTimeout` in `api_client.dart` (90s default) |
| Icon not updating | Run `flutter clean` then rebuild |
| Splash not showing | Run `dart run flutter_native_splash:create` again |
