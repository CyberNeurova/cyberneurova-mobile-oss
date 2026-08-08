package ai.cyberneurova.app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

/**
 * Installs an APK from a file on disk.
 *
 * ## Why PackageInstaller and not `pm install`
 *
 * `pm install` needs a privileged shell — root, our ADB bridge, or Shizuku —
 * and most phones have none of the three. PackageInstaller needs none: the
 * system shows the user its own confirmation dialog, they tap Install, and it
 * happens. That is the path every Android device has, which makes it the one
 * worth building on.
 *
 * A privileged channel is still better when it exists, because it is silent
 * and can run while the user is not looking. But it is an optimisation, not
 * the mechanism, and treating it as the mechanism would have limited this
 * feature to rooted phones.
 *
 * ## What the user still controls
 *
 * Everything. REQUEST_INSTALL_PACKAGES lets us ASK; Android decides. On
 * Android 8+ the user must also have granted this app "install unknown apps",
 * and the confirmation dialog is drawn by the system where we cannot touch it.
 * An agent cannot install something behind the user's back through this path,
 * which is the correct amount of power for it to have.
 */
object ApkInstaller {

    private const val ACTION_RESULT = "ai.cyberneurova.app.INSTALL_RESULT"

    /**
     * Streams [apkPath] into a session and asks the system to install it.
     *
     * Returns a map the Dart side can render: whether the request was
     * ACCEPTED, not whether the install succeeded — success arrives later,
     * after the user answers, and is reported through [onResult].
     */
    fun install(
        context: Context,
        apkPath: String,
        onResult: (status: Int, message: String?) -> Unit,
    ): Map<String, Any?> {
        val file = File(apkPath)
        if (!file.isFile) {
            return mapOf("ok" to false, "error" to "No such file: $apkPath")
        }
        if (file.length() == 0L) {
            return mapOf("ok" to false, "error" to "That file is empty.")
        }

        // The Play build does not declare REQUEST_INSTALL_PACKAGES at all —
        // Play grants it only to apps whose core purpose is installing apps.
        // Without this check that build would send the user to a Settings
        // screen where this app does not appear, and they would toggle
        // nothing and come back none the wiser. Say which build can do it.
        if (!declaresInstallPermission(context)) {
            return mapOf(
                "ok" to false,
                "error" to "This build cannot install apps. The direct " +
                    "download from cyberneurova.ai can — the Play version " +
                    "is not permitted to.",
                "needsPermission" to false,
            )
        }

        // Checked here rather than left to fail inside the session, because
        // "the user has not allowed this app to install apps" is a thing they
        // can fix and needs saying in those words.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            return mapOf(
                "ok" to false,
                "error" to "This app is not allowed to install apps yet. " +
                    "Settings › Apps › CyberNeurova › Install unknown apps.",
                "needsPermission" to true,
            )
        }

        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )

        val sessionId: Int
        try {
            sessionId = installer.createSession(params)
        } catch (e: Throwable) {
            return mapOf("ok" to false, "error" to "Could not start an install session: ${e.message}")
        }

        try {
            installer.openSession(sessionId).use { session ->
                // Streamed rather than read into memory: an APK is tens of
                // megabytes and this runs in the same process as the UI.
                session.openWrite("apk", 0, file.length()).use { out ->
                    file.inputStream().use { input -> input.copyTo(out) }
                    session.fsync(out)
                }

                registerResultReceiver(context, onResult)

                val intent = Intent(ACTION_RESULT).setPackage(context.packageName)
                val pending = PendingIntent.getBroadcast(
                    context,
                    sessionId,
                    intent,
                    // MUTABLE: the system fills in EXTRA_STATUS and, when it
                    // needs the user to confirm, EXTRA_INTENT. An immutable
                    // one comes back empty and the install silently never
                    // reports anything.
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                )
                session.commit(pending.intentSender)
            }
        } catch (e: Throwable) {
            try {
                installer.abandonSession(sessionId)
            } catch (_: Throwable) {
                // Already gone. Nothing useful to do and nothing worth failing
                // the caller over.
            }
            return mapOf("ok" to false, "error" to "Install failed: ${e.message}")
        }

        return mapOf("ok" to true, "sessionId" to sessionId)
    }

    private var receiver: BroadcastReceiver? = null

    private fun registerResultReceiver(
        context: Context,
        onResult: (Int, String?) -> Unit,
    ) {
        receiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: Throwable) {
                // Not registered. Fine — we only care that at most one is.
            }
        }

        val r = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val status = intent.getIntExtra(
                    PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE,
                )
                if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                    // The system's own confirmation. It must be launched from
                    // here, and with NEW_TASK because this arrives on a
                    // broadcast receiver's context, not an activity's.
                    val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                    confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (confirm != null) ctx.startActivity(confirm)
                    return
                }
                onResult(
                    status,
                    intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                )
            }
        }
        receiver = r

        val filter = IntentFilter(ACTION_RESULT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(r, filter)
        }
    }

    /**
     * Whether THIS build asked for REQUEST_INSTALL_PACKAGES.
     *
     * Read from the merged manifest rather than hard-coded per flavour, so a
     * future source set that adds or drops the permission is answered
     * correctly without anyone remembering to update a constant here.
     */
    private fun declaresInstallPermission(context: Context): Boolean = try {
        context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.contains("android.permission.REQUEST_INSTALL_PACKAGES") == true
    } catch (_: Exception) {
        // Cannot read our own package info — assume we have it and let the
        // install attempt produce the real error rather than inventing one.
        true
    }

}
