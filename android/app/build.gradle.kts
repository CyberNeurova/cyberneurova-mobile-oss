import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Sahachiel: release signing reads android/key.properties (git-ignored). Falls
// back to the debug key only when it's absent, so `flutter run --release` still
// works for devs without the keystore — a Play Store upload must use the real key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "ai.cyberneurova.app"
    // Sahachiel: pin compileSdk to 36 instead of flutter.compileSdkVersion (still
    // 34 on the current stable tool). The resolved plugin graph
    // (flutter_plugin_android_lifecycle, pulled by file_picker/image_picker/
    // video_player) now requires its consumers to compile against API 36, so the
    // 34 default fails :file_picker:checkDebugAarMetadata. compileSdk only widens
    // the APIs available at compile time - targetSdk (runtime behaviour) stays on
    // the Flutter default, so this is a build-only bump with no behaviour change.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ai.cyberneurova.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Sahachiel: two distributions, one codebase (docs/shell/14-FLAVOURS.md).
    //
    // The split exists for exactly one reason, and it is not cosmetic: the
    // SELinux W^X restriction that forbids executing a downloaded binary is
    // bound to `targetSdk`, NOT to the Android version. Measured on the A54 /
    // Android 16, same device, same code (SPIKE-RESULTS.md):
    //
    //     targetSdk 36 -> execve of a file we wrote: Permission denied
    //     targetSdk 28 -> execve of a file we wrote: OK
    //
    // So a real Linux userland — PRoot + a Debian/Ubuntu/Kali rootfs with a
    // working `apt` — is reachable at 28 and impossible at 36. Google Play
    // requires a current targetSdk, which is why Termux left the store in
    // 2020. Hence: `play` for the store, `direct` for everyone who wants the
    // distro, from our own site.
    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
            // targetSdk stays on the Flutter default (current) — set in
            // defaultConfig. Play-compatible; tools ship bundled in jniLibs.
        }
        create("direct") {
            dimension = "distribution"
            // The whole point of this flavour. Do not raise it without
            // understanding that doing so silently removes `apt`.
            targetSdk = 28
            versionNameSuffix = "-direct"
            // NOTE: applicationId is deliberately NOT suffixed. A different id
            // would need a second Google OAuth client registered against it
            // (the SHA-1 + package pair) and new deep-link entries, and the
            // two builds would install side by side rather than replacing each
            // other. If we ever want side-by-side, do those two things first.
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // Sahachiel: the pkg_core toolchain (docs/shell/11-PKG-CORE.md) ships CLI
    // tools as lib*.so so they land in nativeLibraryDir — the one directory an
    // app with a current targetSdk may execute from.
    //
    // AGP 8+ defaults useLegacyPackaging to FALSE, which means native libs are
    // never unpacked: they stay mapped from the (uncompressed, page-aligned)
    // APK and nativeLibraryDir resolves to a synthetic "…/base.apk!/lib/<abi>"
    // that is not a real filesystem path. Nothing can be exec'd from it and
    // PrefixBootstrap's symlinks would dangle. Extraction is therefore a hard
    // requirement for bundled tools, NOT a preference.
    //
    // It also costs install size (the lib is stored in the APK *and* on disk),
    // so it's enabled only while we actually ship something — the check below
    // reads the source tree, so adding the first binary flips it automatically
    // and nobody has to remember this comment.

    // The direct flavour ships as ONE APK from our own site — no Play bundle,
    // so no per-ABI splitting, so every user downloads every architecture.
    // Measured on the release build: 41.2 MB, of which x86_64 was 12.0 MB that
    // no consumer Android phone can execute. This build exists for people whose
    // phone IS their computer, often on metered data.
    //
    // Read from the task name for the same reason the signing guard below does:
    // `ndk.abiFilters` in a flavour is UNIONed with what the Flutter plugin
    // puts on defaultConfig, so it cannot subtract, and prebuilt .so files from
    // AARs need a packaging exclude rather than an NDK filter. Verified: with
    // the filter alone x86_64 stayed at 6.5 MB.
    //
    // `play` keeps x86_64 — Play splits per ABI so it costs a phone user
    // nothing, and ChromeOS genuinely runs it. The cost here is that `direct`
    // no longer installs on an x86 emulator, which is acceptable: what that
    // flavour exists to do (PRoot on a real rootfs at targetSdk 28) is a
    // physical-device concern, and `play` still covers emulator work.
    val buildingDirect = gradle.startParameter.taskNames.any {
        it.contains("direct", ignoreCase = true)
    }

    packaging {
        jniLibs {
            if (buildingDirect) {
                excludes += setOf("lib/x86/**", "lib/x86_64/**")
            }
            // Checks EVERY source set, not just main. PRoot lives in
            // src/direct/jniLibs (it is useless on the Play build, which may
            // not execute a downloaded rootfs — shipping ~300 KB of binaries
            // that flavour can never run is pure weight), so a main-only check
            // would leave extraction off for the flavour that needs it most.
            useLegacyPackaging = listOf("main", "direct", "play")
                .map { file("src/$it/jniLibs") }
                .filter { it.exists() }
                .any { dir ->
                    dir.walkTopDown().any { it.isFile && it.name.endsWith(".so") }
                }
        }
    }

    buildTypes {
        release {
            // Flutter turns R8 on for release. Without these rules R8 does not
            // warn, it FAILS — `assemblePlayRelease` produced no artifact at
            // all, so the store build was broken while every debug and profile
            // build worked. See proguard-rules.pro for what each rule is for.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // No keystore on this machine. A release *App Bundle* is the Play
                // upload artifact — silently debug-signing it produces an AAB that
                // Play rejects (and that can never be the real upload key). Hard-fail
                // that path so a misconfigured release is loud, not silently wrong.
                // Local release APKs and `flutter run --release` keep the debug
                // fallback so dev workflows still work without the keystore.
                val buildingReleaseBundle = gradle.startParameter.taskNames.any {
                    it.contains("bundle", ignoreCase = true) &&
                        it.contains("release", ignoreCase = true)
                }
                if (buildingReleaseBundle) {
                    throw GradleException(
                        "Release App Bundle requested but android/key.properties is " +
                            "missing — refusing to debug-sign an AAB (Play would " +
                            "reject it). Provide android/key.properties (keyAlias, " +
                            "keyPassword, storeFile, storePassword) — in CI, decode " +
                            "ANDROID_KEYSTORE_B64 and write it before the build.",
                    )
                }
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Shizuku — lets the app call Android APIs at the ADB shell uid (2000)
    // after the user starts its service over wireless debugging. No root, no
    // computer: Android 11+ pairs wireless debugging on-device.
    //
    // What that buys, measured on a real device (see
    // docs/shell/16-CAPABILITY-ROADMAP.md §2.2): silent package install and
    // uninstall, full package enumeration, and granting ourselves runtime
    // permissions — none of which need the corresponding manifest permissions,
    // so the Play-policy exposure goes away with them.
    //
    // What it does NOT buy: kernel capabilities. Shell's CapEff is zero, so
    // raw sockets and packet capture remain root-only.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")

    // The ADB wire protocol in pure Java — pairing (SPAKE2) plus the
    // connection. Lets US do what Shizuku does, in-app, so the user pairs the
    // phone with its own wireless debugging and never installs anything else.
    //
    // Licence: the sources carry "GPL-3.0-or-later OR Apache-2.0", a dual
    // offer, so we take Apache-2.0 — usable in the closed edition too, with
    // attribution. Checked before depending on it precisely because a
    // GPL-only library would have poisoned that plan.
    implementation("com.github.MuntashirAkon:libadb-android:3.1.1")

    // X.509 generation. Android's platform has no certificate builder, and
    // ADB pairing needs a self-signed cert to present. This is the AOSP sun
    // security classes repackaged, which is what libadb-android's own example
    // uses.
    implementation("com.github.MuntashirAkon:sun-security-android:1.1")

    // Conscrypt: ADB pairing is TLS 1.3, and the platform provider cannot be
    // driven for it without hidden-API access. Bundling the provider avoids
    // that entirely.
    implementation("org.conscrypt:conscrypt-android:2.5.3")
}
