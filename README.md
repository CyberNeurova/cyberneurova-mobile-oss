# CyberNeurova Mobile

> A native Flutter client (iOS + Android) for the CyberNeurova AI chat platform.

![Flutter 3.22+](https://img.shields.io/badge/Flutter-3.22%2B-blue)
![Dart 3.3+](https://img.shields.io/badge/Dart-3.3%2B-blue)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-green.svg)](./LICENSE)

---

## What this is

A single Flutter codebase that ships to **both iOS and Android** as the mobile
client for [cyberneurova.ai](https://cyberneurova.ai). It is a chat app with a
few things bolted on: image generation, voice (text-to-speech and
speech-to-text), file uploads, projects, per-session memory, and a contextual
paywall.

On Android it also hosts an on-device **agent** — a set of surfaces (Research,
Code, Console) where a model can run tools on the phone itself: a real shell
inside a PRoot'd Linux container, a file browser, network probes, and package
installs, all executing locally rather than on a server.

> **This is a client.** It talks to the CyberNeurova backend over HTTPS and
> needs an account to do anything account-scoped (sending messages, paid
> features). The chat shell, settings, and theming are browsable without one.
> The backend is a separate, hosted service — this repository does not include
> it, and the app will not function fully without access to it.

## Platform notes

- **Android** — full feature set, including the on-device agent shell (a PTY in
  a PRoot'd rootfs). Two flavours: `play` (targetSdk current) and `direct`
  (targetSdk 28, for the sideloadable build that can execute an unpacked
  binary).
- **iOS** — chat, media, voice, and the **Research** agent surface. The shell /
  Code / Console surfaces are **not** available: iOS does not permit an app to
  execute a binary it unpacked (kernel-enforced code signing), so those surfaces
  are hidden there by design, not pending. Research works because it uses the
  network, not a shell.

## Getting started

```bash
flutter pub get
flutter run
```

Full environment setup — SDK versions, code generation (`build_runner`),
flavours, and the `--dart-define` configuration the app expects — is in
[`docs/SETUP.md`](./docs/SETUP.md).

To point the app at a backend, pass the API base URL at build time:

```bash
flutter run --dart-define=API_BASE_URL=<your-api-base-url>
```

Google/Apple sign-in and store billing require their own project configuration
(a Google OAuth client, an Apple Service ID, StoreKit / Play Billing products);
without those, email sign-in and the rest of the app still run.

## Tech stack

- **Flutter / Dart**, Riverpod (state), go_router (navigation), freezed +
  json_serializable (models).
- **Android agent runtime**: PRoot + a minimal Linux rootfs, a PTY, and native
  bridges for ADB self-pairing and (optionally) Shizuku — all on-device.

## Documentation

- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — how the app is put together.
- [`docs/DESIGN.md`](./docs/DESIGN.md) — the visual/UX design language.
- [`docs/SETUP.md`](./docs/SETUP.md) — dev environment and build configuration.
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — workflow, standards, and how to
  propose a change.

## License

Licensed under the **Apache License 2.0** — see [`LICENSE`](./LICENSE).
