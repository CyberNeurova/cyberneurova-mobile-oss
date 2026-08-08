package ai.cyberneurova.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build

/**
 * Pairing by typing the code into a notification.
 *
 * ## Why this and not the obvious things
 *
 * The pairing code exists only while the system's pairing dialog is on screen,
 * and every way of getting the user's input while that dialog is up is closed:
 *
 *  - **Switching to our app** closes the dialog and ends the pairing session.
 *    Measured: discovery finds no `_adb-tls-pairing._tcp` service afterwards.
 *  - **A floating overlay** is force-hidden by Android over that dialog
 *    (`mIsForceHiddenNonSystemOverlayWindow=true`) — a deliberate defence
 *    against overlay attacks on security dialogs.
 *  - **Split-screen** works but is OEM-dependent, so it cannot be the flow we
 *    tell everyone to use.
 *
 * The notification shade is the one input surface that is neither an overlay
 * nor an activity switch. Pulling it down pauses the Settings activity without
 * destroying it, so the dialog — and the pairing service — stay alive.
 * **Verified on device: the code was identical before and after opening and
 * closing the shade.**
 *
 * Inline reply has existed since Android 7, so this works everywhere rather
 * than on the devices that happen to allow something.
 */
object PairingNotification {

    private const val CHANNEL_ID = "adb_pairing"
    private const val NOTIFICATION_ID = 4921
    private const val KEY_CODE = "pairing_code"
    const val ACTION_SUBMIT = "ai.cyberneurova.app.SUBMIT_PAIRING_CODE"

    /** Posts the prompt, replacing any previous one. */
    fun show(context: Context, text: String? = null, done: Boolean = false) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "ADB pairing",
                    // HIGH so it stays expanded and reachable while the user
                    // is in Settings. A low-importance notification collapses
                    // into the shade and the reply field becomes a hunt.
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Lets you type the pairing code without " +
                        "leaving the pairing dialog."
                    setShowBadge(false)
                },
            )
        }

        val intent = Intent(context, PairingCodeReceiver::class.java).apply {
            action = ACTION_SUBMIT
            `package` = context.packageName
        }
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            // MUTABLE is required: the system writes the typed text into this
            // intent before delivering it. IMMUTABLE silently drops the reply.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        val action = Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(
                context,
                android.R.drawable.ic_menu_send,
            ),
            "Enter code",
            pending,
        ).addRemoteInput(
            android.app.RemoteInput.Builder(KEY_CODE)
                .setLabel("Six-digit code")
                .build(),
        ).build()

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val body = text
            ?: "Leave the pairing dialog open and type its six digits below. " +
                "Coming back to the app would close that dialog."

        builder
            .setContentTitle(if (done) "Device paired" else "Waiting for the pairing code")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            // Ongoing only while we still need something. Once it is done,
            // an undismissable notification is just litter.
            .setOngoing(!done)
            .setAutoCancel(done)

        // No reply field once there is nothing left to type.
        if (!done) builder.addAction(action)

        nm.notify(NOTIFICATION_ID, builder.build())
    }

    fun update(context: Context, text: String, done: Boolean = false) =
        show(context, text, done)

    fun dismiss(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    fun codeFrom(intent: Intent): String? =
        android.app.RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(KEY_CODE)
            ?.toString()
            ?.trim()

    fun filter() = IntentFilter(ACTION_SUBMIT)
}

/**
 * Receives the typed code and does the pairing, without the app coming to the
 * foreground — which is the entire point, since foregrounding kills the
 * pairing dialog.
 */
class PairingCodeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PairingNotification.ACTION_SUBMIT) return
        val code = PairingNotification.codeFrom(intent)

        if (code == null || code.length != 6 || code.toIntOrNull() == null) {
            PairingNotification.update(
                context,
                "That is not a six-digit code. Try again.",
            )
            return
        }

        PairingNotification.update(context, "Looking for the pairing dialog…")

        val app = context.applicationContext
        // Off the receiver's thread: discovery browses mDNS and pairing does a
        // TLS handshake, and a BroadcastReceiver has about ten seconds before
        // the system considers it stuck.
        val pending = goAsync()
        Thread {
            try {
                val bridge = AdbPairingBridge(app)
                val found = bridge.discoverPairingPort(15_000)
                val port = (found["port"] as? Int) ?: -1
                if (port <= 0) {
                    PairingNotification.update(
                        app,
                        (found["error"] as? String)
                            ?: "No pairing dialog is open.",
                    )
                    return@Thread
                }

                val paired = bridge.pair(port, code)
                if (paired["ok"] != true) {
                    PairingNotification.update(
                        app,
                        "Pairing failed: " +
                            ((paired["error"] as? String) ?: "unknown") +
                            ". Codes expire — reopen the dialog for a new one.",
                    )
                    return@Thread
                }

                val connected = bridge.connect(15_000)
                if (connected["ok"] == true) {
                    // Say what it is actually good for, and prove the uid
                    // rather than assert that it worked.
                    val who = bridge.exec("id -u", 8_000)
                    val uid = (who["stdout"] as? String)?.trim().orEmpty()
                    PairingNotification.update(
                        app,
                        if (uid.isEmpty()) {
                            "Paired and connected. You can close the pairing " +
                                "dialog."
                        } else {
                            "Paired and connected as uid $uid. You can close " +
                                "the pairing dialog."
                        },
                        done = true,
                    )
                } else {
                    PairingNotification.update(
                        app,
                        "Paired. Open the app and tap Connect when ready.",
                        done = true,
                    )
                }
            } catch (t: Throwable) {
                PairingNotification.update(
                    app,
                    "Pairing error: ${t.message ?: t.javaClass.simpleName}",
                )
            } finally {
                pending.finish()
            }
        }.start()
    }
}
