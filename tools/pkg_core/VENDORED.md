# Vendored binaries

Every third-party binary in `android/app/src/main/jniLibs/` is recorded here
with its provenance and the verification that was performed. Nothing lands in
`jniLibs/` without an entry.

---

## PRoot — vendored 2026-08-02

| | |
|---|---|
| Upstream | <https://github.com/termux/proot> (Termux's fork; upstream PRoot is dormant and does not work on modern Android) |
| Repository | `https://packages.termux.dev/apt/termux-main` · suite `stable` · `binary-aarch64` |
| Licence | **GPL-2.0** — see "Obligation" below |

### Packages taken

| Package | Version | SHA-256 of `.deb` | Ships as |
|---|---|---|---|
| `proot` | 5.1.107.89 | `ec9fe38c50cfd49dd31fe360ffbcc3124a945dc1ea16293a8a769303dd724f46` | `libproot.so` |
| `proot` (same .deb) | — | — | `libprootloader.so` (from `libexec/proot/loader`) |
| `libtalloc` | 2.4.3 | `ac81ad623d74c209718b9f3acb2dd702cc8a88c431e820d212229910b4db29da` | `libtalloc.so` |
| `libandroid-shmem` | 0.7 | `0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6` | `libandroid-shmem.so` |

Total added to the APK: **302 KB**.

> **The loader is easy to miss and nothing works without it.** Termux ships it
> at `libexec/proot/loader`, not `bin/` or `lib/`, so an extraction that only
> looks in the usual places drops it silently. PRoot then starts fine,
> `--version` succeeds, and **every guest exec fails** with
> `execve("/bin/sh"): No such file or directory` — whose real cause is the
> *last* entry in PRoot's own hint list. It performs the actual exec of guest
> binaries. Ships as `libprootloader.so`, linked as `proot-loader`, passed via
> `PROOT_LOADER`.

### Verification performed — all four links

1. **`InRelease` GPG signature verified.** Signed by RSA key
   `CC72CF8BA7DBFA0182877D045A897D96E57CF20C` →
   *Termux Releases (Termux automatic builds) <contact@termux.dev>*.
   `gpg --verify` → **Good signature**.
2. **Signing key confirmed independently of the apt server.** The fingerprint
   is asserted in `termux/termux-packages/build-package.sh` on GitHub (as the
   `termux-autobuilds` key), and the key itself was fetched from that GitHub
   repo — *not* from `packages.termux.dev`. Fetching the key from the same host
   that serves the data would be trust-on-first-use and would prove nothing.
3. **`Packages` index hash matches the signed `InRelease`.**
   `d6edf17334bf488d9e9df3648da17580bdb4efa65ce2b7a20f475bf3dd7f0708`.
4. **Each `.deb` SHA-256 matches the verified `Packages` index** (table above).

The first attempt aborted on a malformed URL and refused to proceed rather than
skipping a check — the intended failure mode.

### ELF properties (checked before shipping)

All three: **aarch64, dynamic PIE, `/system/bin/linker64`, LOAD alignment
`0x4000` (16 KB — Android 15 compliant)**, stripped, built with NDK r28c/r29.

`proot` `DT_NEEDED`: `libtalloc.so.2`, `libandroid-shmem.so`, `libc.so`.
`DT_RUNPATH`: `/data/data/com.termux/files/usr/lib` — Termux's prefix, which
does not exist in our app.

### Two things that had to be solved, and why

1. **`libtalloc.so.2` cannot be shipped under that name.** Android's installer
   only extracts files matching `lib*.so`, and `libtalloc.so.2` does not match
   — it would silently never be installed. Shipped as `libtalloc.so`, with the
   SONAME exposed via a symlink in `$PREFIX/lib`
   (`PrefixBootstrap.defaultLibraryAliases`), because the linker looks for the
   literal `DT_NEEDED` string.
2. **`DT_RUNPATH` points into Termux's prefix.** `LD_LIBRARY_PATH` is searched
   *before* `DT_RUNPATH`, so `PrefixBootstrap.libraryPath()` supplies
   `$PREFIX/lib:<nativeLibraryDir>` and resolution succeeds.

### Verified running on device

Samsung SM-A546E, Android 16, `direct` flavour (`targetSdk 28`), real app
process:

```
[startup] linked=3 [cn-arch, cn-hello, proot] libs=[libtalloc.so.2]
[startup] proot exit=0 :: _____ _____              ___
[startup] downloaded-exec=OK
```

`exit=0` with PRoot's version banner. Then the full stack, same device:

```
[startup] linked=4 [cn-arch, cn-hello, proot, proot-loader] libs=[libtalloc.so.2]
[alpine]  proot exit=0
[alpine]    3.21.7                                  <- cat /etc/alpine-release
[alpine]    uid=0(root) gid=0(root) groups=3003,... <- id, inside the guest
[alpine]    aarch64                                 <- uname -m
```

And the package manager, which is the whole point:

```
$ apk update
OK: 25251 distinct packages available

$ apk add nmap
(6/6) Installing nmap (7.95-r1)
OK: 23 MiB in 21 packages

$ nmap --version
Nmap version 7.95 ( https://nmap.org )
Platform: aarch64-alpine-linux-musl
```

Alpine Linux, running on the phone, installing arbitrary packages.

### Obligation

PRoot is **GPL-2.0**, and the owner has accepted this. Distribution of the
`direct` build must carry a written offer to supply the corresponding source
(or the source itself). It applies to PRoot today and to busybox/nmap if those
are added later. **A page on cyberneurova.ai must exist to point at before the
first public `direct` release.**

### Refreshing

Re-run the four checks. Never copy a hash from a previous entry, a mirror, or a
blog post — take it from a freshly GPG-verified `InRelease` → `Packages` chain.

---

## cntool — built in-house 2026-08-02

`tools/pkg_core/cntool.c`, built by `tools/pkg_core/build.sh`. A two-applet
multicall binary (`cn-hello`, `cn-arch`) that exists to prove the bundled-tool
pipeline end to end and to keep it proven — the startup probe runs it on every
debug launch. 4.5 KB. No third-party code, no licence obligation.
