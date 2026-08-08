#!/usr/bin/env bash
# Builds a bundled CLI tool for the app, the way that ACTUALLY works.
#
# The recipe is not obvious and three variants fail before this one — see
# docs/shell/SPIKE-RESULTS.md "Bundled-tool exec spike":
#
#   -static       -> Bionic refuses it: TLS segment underaligned (8, needs 64)
#   -static-pie   -> SIGSEGV, self-relocation doesn't happen
#   dynamic PIE   -> works, and is 4.5 KB instead of 690 KB
#
# Link against Bionic. Android always has /system/bin/linker64 and libc.so, so
# there is nothing to gain from static and a working binary to lose.
set -euo pipefail

NDK="${ANDROID_NDK_HOME:-$HOME/AppData/Local/Android/Sdk/ndk/26.3.11579264}"
HOST="${NDK_HOST:-windows-x86_64}"
BIN="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
OUT="$(dirname "$0")/../../android/app/src/main/jniLibs"

# API 24: the floor for reliable PIE + modern Bionic.
build() {  # <abi> <clang-triple>
  local abi="$1" triple="$2"
  mkdir -p "$OUT/$abi"
  "$BIN/${triple}24-clang" -O2 -fPIE -pie \
    -Wl,-z,max-page-size=16384 \
    -o "$OUT/$abi/libcntool.so" "$(dirname "$0")/cntool.c"
  "$BIN/llvm-strip" "$OUT/$abi/libcntool.so"
  echo "built $abi: $(stat -c%s "$OUT/$abi/libcntool.so" 2>/dev/null || echo ?) bytes"
}

build arm64-v8a   aarch64-linux-android
# build armeabi-v7a armv7a-linux-androideabi   # older 32-bit devices
# build x86_64      x86_64-linux-android        # emulators / ChromeOS
