# R8 keep/warn rules for the release build.
#
# Without this file `assemblePlayRelease` FAILS outright — R8 refuses to
# complete while classes referenced from the dependency graph are missing. It
# is not a warning you can ship past: there was no release APK or AAB at all
# until these rules existed, which means the store build was broken while every
# debug and profile build looked fine.

# Conscrypt ships adapters for platform TLS classes that only exist on old
# Android images (or on the JVM), and references them from code paths that
# never run here. They are absent by design, not missing by mistake.
-dontwarn com.android.org.conscrypt.SSLParametersImpl
-dontwarn org.apache.harmony.xnet.provider.jsse.SSLParametersImpl
-dontwarn org.conscrypt.**

# libadb-android talks the ADB wire protocol using BouncyCastle for SPAKE2 and
# X.509 generation. BouncyCastle reaches for JCE provider classes reflectively;
# stripping them turns wireless-debugging pairing into a runtime crash that
# only reproduces in release.
-dontwarn org.bouncycastle.**
-keep class org.bouncycastle.jcajce.provider.** { *; }
-keep class org.bouncycastle.jce.provider.** { *; }

# Shizuku's binder handshake resolves its provider and interfaces by name.
-keep class rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }
