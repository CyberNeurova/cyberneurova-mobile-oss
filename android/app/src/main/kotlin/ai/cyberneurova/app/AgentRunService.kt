package ai.cyberneurova.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.app.Service

/**
 * Keeps agent work alive when the app is backgrounded, closed, or the screen
 * is off.
 *
 * ## What it is actually protecting
 *
 * The PTYs are child processes of THIS process and the agent run is driven
 * from the Dart isolate. If Android reclaims the process, both die — a build
 * halfway through, a scan halfway through, silently. A foreground service is
 * the only supported way to tell Android this process is doing something the
 * user asked for.
 *
 * ## Sleep, specifically
 *
 * A foreground service survives Doze, but the CPU can still sleep between
 * frames, which stalls a long build. So an active run also holds a
 * PARTIAL_WAKE_LOCK. That is the expensive part, and it is why the discipline
 * below is not optional.
 *
 * ## Power discipline
 *
 * The owner's rule: "if resources are not being used there is no need to have
 * them running." So:
 *
 *  - The wake lock is held only while a run is ACTIVE and released the moment
 *    it finishes — not for the lifetime of the service.
 *  - The service stops itself when the last run ends rather than sitting
 *    resident. A permanently-running service that idles is the failure mode.
 *  - Nothing here polls. State changes arrive from Dart when they happen.
 *
 * A service that lingers with a wake lock is a battery complaint, and a
 * battery complaint is how a feature like this gets switched off for good.
 */
class AgentRunService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    /** Runs actually executing. Only these justify holding the CPU awake. */
    private var activeCount = 0

    /**
     * Live shell sessions, busy or not.
     *
     * These keep the SERVICE alive without holding a wake lock. An open shell
     * at an idle prompt costs nothing to keep — but if Android reclaims the
     * process, its PTY dies with it and the user loses a session they were
     * plainly still using. That is the cheap half of this; the wake lock is
     * the expensive half, and they are counted separately for that reason.
     */
    private var sessionCount = 0

    /**
     * The user asked us to stay awake, from the notification.
     *
     * ## Why this has to exist
     *
     * We know when the AGENT is working, so we can hold the CPU for exactly
     * that long. We do not know when a command the user typed themselves is
     * working: a PTY is always "running a shell", busy or idle, and guessing
     * from output would either hold the lock forever or drop it mid-build.
     *
     * So `apt install` typed by hand gets no protection, and with the screen
     * off Doze can suspend the CPU under it. Rather than pretend otherwise, the
     * notification offers the switch and says what it costs. This is what
     * Termux does, for the same reason.
     */
    private var userWakeLock = false

    override fun onBind(intent: Intent): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopEverything()
                return START_NOT_STICKY
            }
            ACTION_TOGGLE_WAKE -> {
                userWakeLock = !userWakeLock
                syncWakeLock()
                startForeground(NOTIFICATION_ID, build(defaultText))
            }
            else -> {
                activeCount = intent?.getIntExtra(EXTRA_ACTIVE, activeCount)
                    ?: activeCount
                sessionCount = intent?.getIntExtra(EXTRA_SESSIONS, sessionCount)
                    ?: sessionCount
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: defaultText

                if (activeCount <= 0 && sessionCount <= 0) {
                    stopEverything()
                    return START_NOT_STICKY
                }

                // startForeground is safe to call again on an already-started
                // service and is what updates the notification, so there is no
                // separate start/update path to keep in sync.
                startForeground(NOTIFICATION_ID, build(text))
                syncWakeLock()
            }
        }

        // NOT sticky. If Android kills us under memory pressure the run is
        // already gone with the process — restarting an empty service would
        // hold a notification over nothing.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun stopEverything() {
        // The user's request does not outlive the work it was protecting. If
        // it did, the next session would silently inherit a wake lock nobody
        // remembers asking for.
        userWakeLock = false
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * Holds the CPU only while something is genuinely running.
     *
     * Tied to [activeCount] rather than to the service's lifetime, so a
     * session that is merely open costs nothing.
     */
    private fun syncWakeLock() {
        if (activeCount > 0 || userWakeLock) acquireWakeLock() else releaseWakeLock()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "cyberneurova:agent-run",
        ).apply {
            setReferenceCounted(false)
            // A timeout is a backstop, not the mechanism — the release below
            // is what normally ends it. Without one, a crash between acquire
            // and release would drain the battery until reboot.
            acquire(MAX_RUN_MILLIS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun build(text: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Agent work",
                    // LOW: this is a working indicator. Anything higher would
                    // buzz for something the user started deliberately.
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while an agent or shell is running."
                    setShowBadge(false)
                },
            )
        }

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val toggleWake = PendingIntent.getService(
            this,
            2,
            Intent(this, AgentRunService::class.java)
                .setAction(ACTION_TOGGLE_WAKE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, AgentRunService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // The title says which of the two states we are in, because they cost
        // the user very different amounts of battery and they deserve to be
        // able to tell them apart at a glance.
        val title = when {
            activeCount > 0 -> "CyberNeurova is working"
            userWakeLock -> "CyberNeurova is staying awake"
            else -> "CyberNeurova session open"
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(
                if (activeCount > 0) {
                    android.R.drawable.stat_notify_sync
                } else {
                    android.R.drawable.stat_sys_download_done
                },
            )
            .setContentIntent(open)
            // Only un-swipeable while something is genuinely running. An idle
            // session's notification should be dismissible like any other.
            .setOngoing(activeCount > 0 || userWakeLock)
            // A stop the user can reach without opening the app. Anything that
            // holds a wake lock must be stoppable from where it is visible.
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(
                        this,
                        android.R.drawable.ic_menu_close_clear_cancel,
                    ),
                    "Stop",
                    stop,
                ).build(),
            )
            // Offered only when the agent is NOT already holding the CPU —
            // while it is, the switch would do nothing and reading it as a
            // no-op control is worse than not having it.
            .let { b ->
                if (activeCount > 0) {
                    b
                } else {
                    b.addAction(
                        Notification.Action.Builder(
                            android.graphics.drawable.Icon.createWithResource(
                                this,
                                if (userWakeLock) {
                                    android.R.drawable.ic_lock_idle_low_battery
                                } else {
                                    android.R.drawable.ic_lock_idle_alarm
                                },
                            ),
                            if (userWakeLock) "Allow sleep" else "Keep awake",
                            toggleWake,
                        ).build(),
                    )
                }
            }
            .build()
    }

    private val defaultText
        get() = if (userWakeLock && activeCount == 0) {
            "Staying awake for you — tap Allow sleep when you are done"
        } else when {
            activeCount > 0 && sessionCount > 0 ->
                "$activeCount running · $sessionCount ${plural(sessionCount)} open"
            activeCount > 0 -> "$activeCount running on this device"
            // The title already says a session is open, so the body earns its
            // space by saying what to do with that instead of repeating it.
            else -> "Tap to return to your ${plural(sessionCount)}"
        }

    private fun plural(n: Int) = if (n == 1) "shell" else "shells"

    companion object {
        const val ACTION_STOP = "ai.cyberneurova.app.STOP_AGENT_RUN"
        const val ACTION_TOGGLE_WAKE = "ai.cyberneurova.app.TOGGLE_AGENT_WAKE"
        const val EXTRA_TEXT = "text"
        const val EXTRA_ACTIVE = "active"
        const val EXTRA_SESSIONS = "sessions"

        private const val CHANNEL_ID = "agent_run"
        private const val NOTIFICATION_ID = 4922

        /**
         * Backstop for the wake lock, not a run limit.
         *
         * Long enough for a real build on a phone, short enough that a bug
         * cannot flatten the battery overnight.
         */
        private const val MAX_RUN_MILLIS = 30L * 60 * 1000
    }
}
