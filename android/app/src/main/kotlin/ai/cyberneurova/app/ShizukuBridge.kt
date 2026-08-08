package ai.cyberneurova.app

import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku

/**
 * Access to the ADB shell uid (2000) through Shizuku.
 *
 * ## Why this exists
 *
 * Our app runs as `untrusted_app` and prompts for everything. The shell uid
 * holds `INSTALL_PACKAGES`, `DELETE_PACKAGES`, `GRANT_RUNTIME_PERMISSIONS`,
 * `WRITE_SECURE_SETTINGS`, `READ_LOGS` and `DUMP`, can enumerate every package
 * without `QUERY_ALL_PACKAGES`, and can execute from `/data/local/tmp`. All
 * measured on a real device — see `docs/shell/16-CAPABILITY-ROADMAP.md` §2.2.
 *
 * Crucially the user reaches it **without root and without a computer**:
 * Android 11+ pairs wireless debugging on-device, and Shizuku turns that into
 * a service apps can bind to.
 *
 * Routing through here also means we do **not** declare those permissions in
 * our manifest, so there is no Play-policy exposure to argue about.
 *
 * ## What it deliberately does not do
 *
 * Shell holds no kernel capabilities — `CapEff` is zero. Raw sockets, packet
 * capture and monitor mode stay root-only, and nothing here pretends
 * otherwise.
 *
 * ## One primitive, not an API per feature
 *
 * The single useful call is "run this command as uid 2000". `pm install`,
 * `pm uninstall`, `pm list packages`, `settings put` and `appops` all fall out
 * of it. Wrapping each in its own binder method would triple the surface and
 * buy nothing.
 */
class ShizukuBridge(private val onPermissionResult: (Int, Int) -> Unit) {

    companion object {
        /** Our own request code; Shizuku hands it back on the callback. */
        const val REQUEST_CODE = 4919
    }

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            onPermissionResult(requestCode, grantResult)
        }

    fun attach() {
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    fun detach() {
        try {
            Shizuku.removeRequestPermissionResultListener(permissionListener)
        } catch (_: Throwable) {
            // Shizuku may already be gone; detaching from nothing is fine.
        }
    }

    /**
     * Current state, as a plain string the Dart side maps to an enum.
     *
     * Deliberately distinguishes "no service running" from "running but not
     * yet permitted" — they need different UI. The first tells the user to
     * start Shizuku; the second is one tap away from working.
     */
    fun status(): String = try {
        when {
            // pingBinder() is the only honest liveness check. Shizuku's
            // service dies on reboot and the class stays loaded, so asking
            // anything else can report a service that is not there.
            !Shizuku.pingBinder() -> "unavailable"
            Shizuku.isPreV11() -> "unsupported"
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED ->
                "granted"
            Shizuku.shouldShowRequestPermissionRationale() -> "denied"
            else -> "present"
        }
    } catch (_: Throwable) {
        // Shizuku not installed at all: the class fails to link. Not an
        // error condition — it is the common case.
        "unavailable"
    }

    /** The uid the service runs as: 2000 for ADB, 0 if started by root. */
    fun serviceUid(): Int = try {
        if (Shizuku.pingBinder()) Shizuku.getUid() else -1
    } catch (_: Throwable) {
        -1
    }

    fun requestPermission() {
        try {
            if (Shizuku.pingBinder() &&
                Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED
            ) {
                Shizuku.requestPermission(REQUEST_CODE)
            }
        } catch (_: Throwable) {
            // Nothing to request against; status() already says so.
        }
    }

    /**
     * Runs [command] via `sh -c` at the service's uid and collects its output.
     *
     * Blocking, so callers must be off the main thread. [timeoutMs] guards
     * against a command that never returns holding a thread forever — the
     * agent is allowed to run anything, including things that hang.
     */
    fun exec(command: String, timeoutMs: Long): Map<String, Any?> {
        return try {
            val process = newShellProcess(arrayOf("sh", "-c", command))
                ?: return mapOf(
                    "ok" to false,
                    "exitCode" to -1,
                    "stdout" to "",
                    "stderr" to "Shizuku newProcess is unavailable on this " +
                        "version of the API.",
                )
            val out = process.inputStream.bufferedReader().readText()
            val err = process.errorStream.bufferedReader().readText()

            val finished = process.waitForTimeout(timeoutMs)
            if (!finished) {
                process.destroy()
                return mapOf(
                    "ok" to false,
                    "exitCode" to -1,
                    "stdout" to out,
                    "stderr" to "Timed out after ${timeoutMs}ms.",
                )
            }
            val code = process.exitValue()
            mapOf(
                "ok" to (code == 0),
                "exitCode" to code,
                "stdout" to out,
                "stderr" to err,
            )
        } catch (t: Throwable) {
            mapOf(
                "ok" to false,
                "exitCode" to -1,
                "stdout" to "",
                "stderr" to (t.message ?: t.javaClass.simpleName),
            )
        }
    }

    /**
     * `Shizuku.newProcess`, which the API marks private.
     *
     * It is the only way to run an arbitrary command at the service uid — the
     * public surface exposes binder transactions, not process spawning — and
     * every app doing this reaches it the same way. Reflection here is on
     * *our own dependency*, not on an Android hidden API, so it is unaffected
     * by the non-SDK interface restrictions.
     *
     * Returns null rather than throwing if a future Shizuku removes or renames
     * it: the caller degrades to "unavailable", which is a state the UI
     * already handles, instead of crashing.
     */
    private fun newShellProcess(cmd: Array<String>): Process? = try {
        val m = Shizuku::class.java.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java,
        )
        m.isAccessible = true
        m.invoke(null, cmd, null, null) as? Process
    } catch (_: Throwable) {
        null
    }

    /**
     * [Process.waitFor] with a deadline.
     *
     * `waitFor(long, TimeUnit)` exists on the JDK Process but Shizuku's remote
     * process is its own type, so poll instead. 25 ms keeps a short command
     * responsive without spinning.
     */
    private fun Process.waitForTimeout(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            try {
                exitValue()
                return true
            } catch (_: IllegalThreadStateException) {
                Thread.sleep(25)
            }
        }
        return false
    }
}

/** Wires [ShizukuBridge] onto a method channel. */
fun ShizukuBridge.handle(call: String, args: Map<*, *>?, result: MethodChannel.Result) {
    when (call) {
        "shizukuStatus" -> result.success(status())
        "shizukuUid" -> result.success(serviceUid())
        "shizukuRequestPermission" -> {
            requestPermission()
            result.success(null)
        }
        else -> result.notImplemented()
    }
}
