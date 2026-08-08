#!/usr/bin/env bash
# Build BusyBox against Bionic with the Android NDK.
#
# Why not a distro build: Alpine's busybox-static is musl, and Android's
# seccomp filter kills it with SIGSYS the moment an app spawns it. Termux's is
# Bionic but pulls in Termux's own libandroid-selinux.so. Building it ourselves
# gives a binary with no dependency beyond Android's own libc.
#
# Config strategy: allnoconfig, then enable ONLY the decompressors we need.
# BusyBox's full defconfig assumes glibc in a dozen places Android lacks
# (shadow.h, utmp, crypt, getspnam); a minimal config never reaches them.
set -euo pipefail

NDK="$HOME/ndk/android-ndk-r26d"
BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
SRC="$HOME/bb/busybox-1.37.0"
API=24

# ABI coverage. arm64-v8a is the only one we ship binaries for today, which
# means armeabi-v7a and x86_64 devices install fine, fall back to Android's own
# shell, and cannot run a distro at all. That degrades correctly (the PRoot
# applets are absent, so canInstallDistros reports false and the distro list is
# hidden) but it silently costs those users the whole Linux feature.
#
# Building busybox for the others is trivial — uncomment. Shipping it alone
# does NOT enable distros: PRoot, its loader and libtalloc must be vendored for
# the same ABI from Termux, which publishes arm/i686/x86_64 alongside aarch64.
# Ship all four per ABI, or none.
ABIS="${ABIS:-arm64-v8a}"
# ABIS="arm64-v8a armeabi-v7a x86_64"

triple_for() {
  case "$1" in
    arm64-v8a)   echo aarch64-linux-android ;;
    armeabi-v7a) echo armv7a-linux-androideabi ;;
    x86_64)      echo x86_64-linux-android ;;
    *) echo "unknown abi $1" >&2; exit 1 ;;
  esac
}

CLANG="$BIN/aarch64-linux-android$API-clang"
test -x "$CLANG" || { echo "no clang at $CLANG"; exit 1; }

cd "$SRC"
make distclean >/dev/null 2>&1 || true
make allnoconfig >/dev/null

enable() { sed -i "s|^# $1 is not set|$1=y|; s|^$1=.*|$1=y|" .config; grep -q "^$1=y" .config || echo "$1=y" >> .config; }

# The `busybox` applet itself. allnoconfig leaves it out, and without it the
# multicall dispatcher has no way to be told which applet to run: `busybox tar`
# answers "applet not found" even though tar is compiled in. Everything else
# here is useless without it.
enable CONFIG_BUSYBOX

# The point of the exercise.
enable CONFIG_TAR
enable CONFIG_FEATURE_TAR_AUTODETECT
enable CONFIG_FEATURE_TAR_LONG_OPTIONS
enable CONFIG_FEATURE_TAR_GNU_EXTENSIONS
enable CONFIG_FEATURE_SEAMLESS_XZ
enable CONFIG_FEATURE_SEAMLESS_GZ
enable CONFIG_FEATURE_SEAMLESS_BZ2
enable CONFIG_UNXZ
enable CONFIG_XZCAT
enable CONFIG_GUNZIP
enable CONFIG_ZCAT
enable CONFIG_BUNZIP2
enable CONFIG_BZCAT
enable CONFIG_LONG_OPTS
enable CONFIG_SHOW_USAGE

# Android needs PIE; the 16 KB page flag matches what the app's other bundled
# binaries are linked with (devices with 16 KB pages refuse otherwise).
sed -i 's|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS="-fPIE -Wno-error"|' .config
sed -i 's|^CONFIG_EXTRA_LDFLAGS=.*|CONFIG_EXTRA_LDFLAGS="-pie -Wl,-z,max-page-size=16384"|' .config
grep -q '^CONFIG_EXTRA_CFLAGS=' .config || echo 'CONFIG_EXTRA_CFLAGS="-fPIE -Wno-error"' >> .config
grep -q '^CONFIG_EXTRA_LDFLAGS=' .config || echo 'CONFIG_EXTRA_LDFLAGS="-pie -Wl,-z,max-page-size=16384"' >> .config

# Static would be simpler but Bionic refuses it (TLS segment underaligned);
# dynamic against Android's own libc is the combination that works.
sed -i 's|^CONFIG_STATIC=y|# CONFIG_STATIC is not set|' .config

yes "" | make oldconfig >/dev/null 2>&1 || true

echo "=== applets enabled ==="
grep -E '^CONFIG_(TAR|UNXZ|XZCAT|GUNZIP|ZCAT|BUNZIP2|BZCAT)=y' .config || true

make -j"$(nproc)" \
  ARCH=arm64 \
  CROSS_COMPILE="$BIN/llvm-" \
  CC="$CLANG" \
  HOSTCC=gcc \
  SKIP_STRIP=n \
  2>&1 | tail -25

echo "=== result ==="
ls -la busybox
file busybox
