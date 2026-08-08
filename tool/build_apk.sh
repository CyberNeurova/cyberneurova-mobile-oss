#!/usr/bin/env bash
# Build an APK and REFUSE to hand back a stale one.
#
# Gradle's up-to-date check can decide `packagePlayProfile` needs no work even
# after the Dart AOT step has produced a new `app.so`. The build prints
# "√ Built ... app-play-profile.apk", the install prints "Success", and the
# phone keeps running code from days ago. Everything downstream of that — every
# screenshot, every "verified on device" — is then a statement about the wrong
# binary, which is worse than a build failure because it looks like it worked.
#
# So: compile, then compare the snapshot Gradle just produced against the one
# actually inside the APK. If they differ, clean and build again.
#
# Usage: tool/build_apk.sh [profile|release|debug] [play|direct]
set -euo pipefail

MODE="${1:-profile}"
FLAVOR="${2:-play}"
ABI="arm64-v8a"

cd "$(dirname "$0")/.."

# playProfile, directRelease, …
CAP_MODE="$(printf '%s' "${MODE:0:1}" | tr '[:lower:]' '[:upper:]')${MODE:1}"
VARIANT="${FLAVOR}${CAP_MODE}"
SNAPSHOT="build/app/intermediates/flutter/${VARIANT}/${ABI}/app.so"
APK="build/app/outputs/flutter-apk/app-${FLAVOR}-${MODE}.apk"

# Build-time configuration lives in `.env` (git-ignored, see .env.example) and
# reaches the app as --dart-define values. Missing it does not fail the build,
# it quietly changes it: GOOGLE_INSTALLED_CLIENT_ID has no default, so the
# browser OAuth fallback stays dormant and a phone that cannot use Play services
# has no way to sign in with Google at all. Say so rather than shipping it.
DEFINES=()
if [ -f .env ]; then
  DEFINES+=(--dart-define-from-file=.env)
else
  echo "! No .env — building without it. GOOGLE_INSTALLED_CLIENT_ID and any"
  echo "  API_BASE_URL override will be absent (see .env.example)."
fi

build() {
  # The direct build is a single APK from our own site, so it carries every ABI
  # it is given — and x86_64 was a third of the download that no phone can run.
  # `play` keeps all of them: Play splits per ABI, and ChromeOS is real.
  if [ "${FLAVOR}" = "direct" ]; then
    flutter build apk "--${MODE}" --flavor "${FLAVOR}" "${DEFINES[@]}"       --target-platform android-arm,android-arm64
  else
    flutter build apk "--${MODE}" --flavor "${FLAVOR}" "${DEFINES[@]}"
  fi
}

# Compared by GNU build-id, not by hash: Gradle strips the libraries it
# packages, so the compiled snapshot and the packaged one never hash alike even
# when they are the same build. The build-id note survives stripping.
#
# Debug builds ship a JIT kernel, not an AOT snapshot — nothing to compare.
matches() {
  [ "${MODE}" = "debug" ] && return 0
  [ -f "${SNAPSHOT}" ] || return 1
  [ -f "${APK}" ] || return 1
  local a b
  a="$(python3 tool/aot_build_id.py "${SNAPSHOT}")" || return 1
  b="$(python3 tool/aot_build_id.py "${APK}" "lib/${ABI}/libapp.so")" || return 1
  [ "${a}" = "${b}" ]
}

# Second half of the same question: the packaged snapshot can agree with the
# compiled one and BOTH be older than the code. Compare against the newest Dart
# source rather than trusting either tool's up-to-date check.
fresh() {
  [ "${MODE}" = "debug" ] && return 0
  [ -f "${SNAPSHOT}" ] || return 1
  local newest
  newest="$(find lib pubspec.yaml -newer "${SNAPSHOT}" -print -quit 2>/dev/null)"
  [ -z "${newest}" ]
}

build
if matches && fresh; then
  echo "✓ ${APK} carries the snapshot this build just produced."
  exit 0
fi
if ! fresh; then
  echo "✗ Dart sources are newer than the compiled snapshot — the AOT step was"
  echo "  skipped. Cleaning and rebuilding."
fi

if ! matches; then
  echo "✗ ${APK} does NOT carry this build's Dart snapshot — Gradle reused a"
  echo "  stale package. Cleaning and rebuilding."
fi
flutter clean >/dev/null
build
if matches && fresh; then
  echo "✓ ${APK} is current after the clean rebuild."
  exit 0
fi

echo "✗ Still stale after a clean build. Do not install this APK." >&2
exit 1
