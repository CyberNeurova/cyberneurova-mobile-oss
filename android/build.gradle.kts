allprojects {
    repositories {
        google()
        mavenCentral()
        // libadb-android — the ADB wire protocol, so the app can pair with
        // the phone's own wireless debugging and reach uid 2000 without the
        // user installing a separate app. JitPack is its only publisher.
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Sahachiel: a resolved transitive plugin (flutter_plugin_android_lifecycle, pulled
// in by file_picker / image_picker / video_player) now requires every consumer to
// compile against Android API 36. But Flutter plugin modules default their compileSdk
// to flutter.compileSdkVersion - still 34 on the current stable tool - and that does
// NOT inherit the app module's value, so :file_picker:checkDebugAarMetadata fails the
// whole build. Raise the floor to 36 for every Android subproject here. This only
// widens the compile-time API surface; targetSdk (runtime opt-in) and minSdk (install
// range) are untouched, so there is no device-behaviour change.
subprojects {
    val proj = this
    val bumpCompileSdk = {
        val androidExt = proj.extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
    // Override the plugin's own compileSdk (set from flutter.compileSdkVersion = 34
    // during its evaluation), so register in afterEvaluate to run last. The block
    // above force-evaluates :app via evaluationDependsOn(":app"); afterEvaluate on an
    // already-evaluated project throws InvalidUserCodeException (a GradleException, not
    // IllegalStateException). :app already pins compileSdk 36 in its own build.gradle,
    // so for that one project there is nothing to do - just swallow the throw.
    try {
        proj.afterEvaluate { bumpCompileSdk() }
    } catch (e: Exception) {
        // :app, already evaluated and already on compileSdk 36 - no-op.
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
