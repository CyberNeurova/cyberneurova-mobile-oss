# jniLibs — bundled CLI tools

Binaries dropped here are the **only** ones the app can execute. Everything we
write to our own data directory is labelled `app_data_file`, which SELinux
denies `execute` on from API 29 — measured on our hardware, see
`docs/shell/SPIKE-RESULTS.md`.

Layout:

```
jniLibs/
  arm64-v8a/libbusybox.so      ← every current device
  armeabi-v7a/libbusybox.so    ← old 32-bit devices
  x86_64/libbusybox.so         ← emulators, ChromeOS
```

Three rules, all load-bearing:

1. **Name it `lib<name>.so`.** The installer only extracts that pattern and
   bundletool strips the rest — a correctly-built binary under any other name
   simply won't be on the device.
2. **Static, or Bionic-linked.** A glibc binary from a desktop distro fails at
   exec. Build with the NDK toolchain.
3. **Adding the first `.so` here flips `useLegacyPackaging` on** (see
   `android/app/build.gradle.kts`), which is what makes the installer extract
   to a real path instead of memory-mapping from the APK. Automatic — but it
   does increase install size, so don't park unused binaries here.

Then register the applet names in `PrefixBootstrap.defaultToolset` so they get
symlinked onto `$PATH`, and verify on a device with `which <name>`.

Full procedure and the licence/compliance note: `docs/shell/11-PKG-CORE.md`.
