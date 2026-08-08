package ai.cyberneurova.app

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Pending permission result, so the Dart side can await the user's answer
     * to Shizuku's dialog rather than poll for it.
     */
    private var pendingPermission: MethodChannel.Result? = null

    /** Same idea, for the system's POST_NOTIFICATIONS dialog. */
    private var pendingNotificationPermission: MethodChannel.Result? = null

    private val notificationRequestCode = 4931

    /**
     * In-app ADB pairing: the same uid-2000 access Shizuku provides, without
     * asking the user to install anything.
     */
    private val adb by lazy { AdbPairingBridge(applicationContext) }

    private val shizuku by lazy {
        ShizukuBridge { requestCode, grantResult ->
            if (requestCode == ShizukuBridge.REQUEST_CODE) {
                pendingPermission?.success(
                    grantResult == android.content.pm.PackageManager.PERMISSION_GRANTED,
                )
                pendingPermission = null
            }
        }
    }

    /**
     * Facts about the app's own install layout that no Flutter plugin exposes.
     *
     * Specifically `nativeLibraryDir` — the ONE directory an app with a modern
     * targetSdk can execute a binary from. Everything else we own is labelled
     * `app_data_file`, which SELinux denies execute on since API 29 (measured
     * on our own hardware, see docs/shell/SPIKE-RESULTS.md). The path contains
     * an install-specific hash and changes on every app update, so it must be
     * asked for at runtime rather than derived or cached across versions.
     */
    private val runtimeChannel = "ai.cyberneurova.app/device_runtime"

    override fun onDestroy() {
        shizuku.detach()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationRequestCode) return
        // An empty grantResults means the request was cancelled, which is a
        // denial as far as the caller is concerned — never leave the future
        // hanging, the UI awaits it.
        pendingNotificationPermission?.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        pendingNotificationPermission = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shizuku.attach()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, runtimeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" ->
                        result.success(applicationInfo.nativeLibraryDir)

                    // Which ABIs the installer could have picked. A split APK
                    // carries only one, so this answers "which jniLibs flavour
                    // is on disk" — worth having in a bug report when a
                    // bundled tool turns up missing on one device only.
                    "supportedAbis" ->
                        result.success(android.os.Build.SUPPORTED_ABIS.toList())

                    // Whether the agent-run notification can actually be seen.
                    //
                    // The foreground service posts one whenever a run keeps
                    // working with the app in the background, and it carries
                    // the only Stop button that exists outside the app. With
                    // POST_NOTIFICATIONS denied the system drops it silently:
                    // the service still runs, and the user has no sign of it
                    // and no way to stop it. Verified on the handset.
                    "canPostNotifications" ->
                        result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                                ContextCompat.checkSelfPermission(
                                    this,
                                    android.Manifest.permission.POST_NOTIFICATIONS,
                                ) == PackageManager.PERMISSION_GRANTED,
                        )

                    // Asks once and resolves with the answer. Below API 33 the
                    // permission does not exist and notifications are allowed
                    // by default, so this is an immediate true rather than a
                    // dialog that can never appear.
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                        } else if (ContextCompat.checkSelfPermission(
                                this,
                                android.Manifest.permission.POST_NOTIFICATIONS,
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            pendingNotificationPermission?.success(false)
                            pendingNotificationPermission = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                notificationRequestCode,
                            )
                        }
                    }

                    "shizukuStatus" -> result.success(shizuku.status())

                    "shizukuUid" -> result.success(shizuku.serviceUid())

                    // Resolves when the user answers Shizuku's dialog, so the
                    // UI can await it instead of polling.
                    "shizukuRequestPermission" -> {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        shizuku.requestPermission()
                    }

                    // The one primitive worth having: run a command at the
                    // service's uid. pm install/uninstall, package
                    // enumeration and settings all fall out of it, so there is
                    // no reason for a binder method per feature.
                    "shizukuExec" -> {
                        val cmd = call.argument<String>("command") ?: ""
                        val timeout =
                            (call.argument<Int>("timeoutMs") ?: 30000).toLong()
                        Thread {
                            val r = shizuku.exec(cmd, timeout)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    // ── in-app ADB pairing ────────────────────────────
                    // All off the main thread: pairing does a TLS handshake
                    // and connect browses mDNS, both of which block.
                    "adbPair" -> {
                        val port = call.argument<Int>("port") ?: 0
                        val code = call.argument<String>("code") ?: ""
                        Thread {
                            val r = adb.pair(port, code)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    "adbConnect" -> {
                        val t = (call.argument<Int>("timeoutMs")
                            ?: AdbPairingBridge.DEFAULT_TIMEOUT_MS.toInt()).toLong()
                        Thread {
                            val r = adb.connect(t)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    // Takes the user straight to the screen with the code
                    // on it. Written instructions to "find Developer options"
                    // are where this flow loses people.
                    "openWirelessDebugging" -> {
                        val ok = try {
                            startActivity(
                                android.content.Intent(
                                    android.provider.Settings
                                        .ACTION_APPLICATION_DEVELOPMENT_SETTINGS,
                                ).addFlags(
                                    android.content.Intent.FLAG_ACTIVITY_NEW_TASK,
                                ),
                            )
                            true
                        } catch (_: Throwable) {
                            false
                        }
                        result.success(ok)
                    }

                    "adbDiscoverPairingPort" -> {
                        val t = (call.argument<Int>("timeoutMs") ?: 20000).toLong()
                        Thread {
                            val r = adb.discoverPairingPort(t)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    // The prompt whose inline reply does the pairing. The
                    // app must NOT be foregrounded to use it — that is the
                    // whole reason it exists.
                    "showPairingNotification" -> {
                        PairingNotification.show(applicationContext)
                        result.success(true)
                    }

                    "dismissPairingNotification" -> {
                        PairingNotification.dismiss(applicationContext)
                        result.success(null)
                    }

                    "adbIsConnected" -> result.success(adb.isConnected())

                    // Has this device ever been paired? The key on disk is
                    // the evidence, and it outlives both reboots and the
                    // wireless-debugging toggle.
                    "adbIsPaired" -> result.success(adb.isPaired())

                    // Whether wireless debugging is switched on RIGHT NOW.
                    //
                    // Android clears this on every reboot, and it is the
                    // reason Connect fails almost every time it fails. Without
                    // it the app can only browse mDNS for ten seconds, find
                    // nothing, and guess at why. A read of the global setting
                    // answers the same question instantly and truthfully.
                    "adbWirelessEnabled" -> result.success(
                        try {
                            android.provider.Settings.Global.getInt(
                                contentResolver,
                                "adb_wifi_enabled",
                                0,
                            ) == 1
                        } catch (_: Throwable) {
                            // Unreadable on this ROM: say null rather than
                            // "off", so the UI keeps quiet instead of stating
                            // something it does not know.
                            null
                        },
                    )

                    "adbConnectionInfo" -> {
                        Thread {
                            val r = adb.connectionInfo()
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    "adbDisconnect" -> {
                        adb.disconnect()
                        result.success(null)
                    }

                    "adbExec" -> {
                        val cmd = call.argument<String>("command") ?: ""
                        val t = (call.argument<Int>("timeoutMs") ?: 30000).toLong()
                        Thread {
                            val r = adb.exec(cmd, t)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    // ── background execution ──────────────────────────
                    // One method, not three. Dart owns the count of active
                    // runs; the service only reflects it. Keeping the
                    // arithmetic on one side is what stops the notification
                    // and the wake lock from disagreeing.
                    "setActiveRuns" -> {
                        val active = call.argument<Int>("active") ?: 0
                        val sessions = call.argument<Int>("sessions") ?: 0
                        val text = call.argument<String>("text")
                        val ctx = applicationContext
                        val intent = Intent(ctx, AgentRunService::class.java)
                            .putExtra(AgentRunService.EXTRA_ACTIVE, active)
                            .putExtra(AgentRunService.EXTRA_SESSIONS, sessions)
                            .putExtra(AgentRunService.EXTRA_TEXT, text)
                        val ok = try {
                            if (active > 0 || sessions > 0) {
                                ContextCompat.startForegroundService(ctx, intent)
                            } else {
                                // Nothing left: tear the whole thing down
                                // rather than leave a service resident behind
                                // a "0 running" notification.
                                intent.action = AgentRunService.ACTION_STOP
                                ctx.startService(intent)
                            }
                            true
                        } catch (_: Throwable) {
                            // startForegroundService throws if the app is in
                            // the background without an exemption. A run that
                            // cannot be protected is still a run — it just
                            // loses the guarantee, so report and carry on.
                            false
                        }
                        result.success(ok)
                    }

                    // ── install an APK ────────────────────────────────
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        val r = ApkInstaller.install(applicationContext, path) { status, msg ->
                            // The outcome arrives after the user answers the
                            // system dialog, long after this call returned.
                            // Pushed rather than returned, so the UI can react
                            // without polling for a package that may never
                            // appear.
                            runOnUiThread {
                                MethodChannel(
                                    flutterEngine.dartExecutor.binaryMessenger,
                                    runtimeChannel,
                                ).invokeMethod(
                                    "onInstallResult",
                                    mapOf("status" to status, "message" to msg),
                                )
                            }
                        }
                        result.success(r)
                    }

                    "canInstallApks" -> {
                        val ok = if (android.os.Build.VERSION.SDK_INT >=
                            android.os.Build.VERSION_CODES.O
                        ) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(ok)
                    }

                    // Takes the user to the one screen that grants it. Written
                    // directions to "Settings › Apps › …" are where this loses
                    // people, exactly as with wireless debugging.
                    "openInstallPermission" -> {
                        val ok = try {
                            startActivity(
                                Intent(
                                    android.provider.Settings
                                        .ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    android.net.Uri.parse("package:$packageName"),
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                            true
                        } catch (_: Throwable) {
                            false
                        }
                        result.success(ok)
                    }

                    // ── mDNS ──────────────────────────────────────────
                    // Off the main thread: browsing blocks for the whole
                    // timeout by design.
                    "mdnsDiscover" -> {
                        val t = (call.argument<Int>("timeoutMs") ?: 5000).toLong()
                        val types = call.argument<List<String>>("types")
                        Thread {
                            val r = NsdDiscovery.discover(
                                applicationContext,
                                t,
                                types?.takeIf { it.isNotEmpty() }
                                    ?: NsdDiscovery.defaultTypes,
                            )
                            runOnUiThread { result.success(r) }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
