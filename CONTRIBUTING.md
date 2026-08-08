# Contributing

Thanks for your interest in improving CyberNeurova Mobile. This is an
Apache-2.0 project; by contributing you agree your work is licensed under the
[`LICENSE`](./LICENSE).

## Getting set up

See [`docs/SETUP.md`](./docs/SETUP.md) for SDK versions, code generation, and the
build-time configuration the app expects. In short:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed / json models
flutter analyze
flutter test
```

## Standards

- **State**: Riverpod. Prefer `Notifier`/`AsyncNotifier` over ad-hoc
  `ChangeNotifier`. Don't hold `BuildContext` across an `await`.
- **Navigation**: `go_router` named routes.
- **Models**: `freezed` + `json_serializable`. Generated `*.g.dart` /
  `*.freezed.dart` files are not committed; run `build_runner`.
- **Localization**: user-facing strings go through `AppL10n.of(context)`, not
  hardcoded English. Server errors render via `userMessageFor(context, e)`.
- **Match the surrounding code** — comment density, naming, and idiom. Read a
  file before changing it.

## Security-sensitive by nature

The app handles auth tokens, personal data, payments, and device hardware
(camera, mic, photo library). Treat every change with that in mind:

- Use `AuthedNetworkImage` (not plain `CachedNetworkImage`) for any URL pointing
  at the backend — it attaches the Bearer header only when the origin is ours,
  so a token is never sent off-origin.
- **Never** log or transmit Bearer tokens off-origin.
- Don't weaken the sandbox boundary in the on-device shell code without
  understanding `ShellSession`'s containment checks.
- Don't add a permission without a clear, declarable reason.

## Testing

- `flutter analyze` must be clean.
- `flutter test` must pass (the suite is substantial — add a test with a
  behavioural change, and make sure it fails without your fix before it passes
  with it).
- For UI or device-facing changes, test on a **real device** (iOS, Android, or
  both) and say which in the PR.
- Bump the build number in `pubspec.yaml` (`version: x.y.z+N`) on any store
  upload — stores reject duplicate build numbers.

## Pull requests

Use the PR template. Be specific about what changed, why, how you validated it,
and the worst case if it ships wrong. "Tested locally" without detail isn't
reviewable.

## A note on the backend

This app is a client for a separate, hosted backend that is not part of this
repository. Changes that touch API-facing code should be described precisely in
the PR (endpoint, payload, expected behaviour) so a reviewer can reason about
the contract without access to the server.
