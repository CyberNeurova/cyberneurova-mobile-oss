package ai.cyberneurova.app

import android.content.Context
import android.os.Build
import android.sun.security.x509.AlgorithmId
import android.sun.security.x509.CertificateAlgorithmId
import android.sun.security.x509.CertificateIssuerName
import android.sun.security.x509.CertificateSerialNumber
import android.sun.security.x509.CertificateSubjectName
import android.sun.security.x509.CertificateValidity
import android.sun.security.x509.CertificateVersion
import android.sun.security.x509.CertificateX509Key
import android.sun.security.x509.X500Name
import android.sun.security.x509.X509CertImpl
import android.sun.security.x509.X509CertInfo
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.android.AdbMdns
import io.github.muntashirakon.adb.AdbPairingRequiredException
import java.io.File
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date
import java.util.concurrent.TimeUnit

/**
 * Pairs with the phone's OWN wireless debugging and runs commands at uid 2000.
 *
 * ## Why, when Shizuku already does this
 *
 * Shizuku is a separate app the user must find, install and trust. This is the
 * same mechanism inside our process: the user opens Developer options →
 * Wireless debugging, reads a six-digit code, types it here, done. Nothing
 * else to install.
 *
 * That matters twice. It is a better first run, and the open-source edition
 * should not need a third-party app to be useful.
 *
 * ## What it is
 *
 * ADB over TCP to loopback. Android 11+ runs wireless debugging on the device
 * itself, so the phone is both client and target — nothing crosses the
 * network. Pairing is SPAKE2 with the code as the shared secret; afterwards
 * the device trusts our RSA key and we reconnect without pairing again.
 *
 * Commands then execute as **uid 2000**: `INSTALL_PACKAGES`,
 * `DELETE_PACKAGES`, `GRANT_RUNTIME_PERMISSIONS`, `WRITE_SECURE_SETTINGS`,
 * `READ_LOGS`, `DUMP`. Not root — `CapEff` is zero, so raw sockets stay out
 * of reach and nothing here pretends otherwise.
 *
 * ## Lifetime, which callers must respect
 *
 * The **pairing** survives reboots; the device remembers our key. The
 * wireless debugging **service** does not — it is off until the user turns it
 * back on, and its port is different every time. So connect failures are
 * ordinary, not an error state to alarm about, and the port is discovered
 * over mDNS rather than remembered.
 */
class AdbPairingBridge(private val context: Context) {

    /**
     * Our ADB identity, persisted so the user pairs once rather than every
     * launch. Key and certificate live in the app's private storage — the
     * device trusts this key after pairing, so it is a credential.
     */
    private class Manager(context: Context) : AbsAdbConnectionManager() {
        private val privateKey: PrivateKey
        private val certificate: Certificate

        init {
            setApi(Build.VERSION.SDK_INT)

            val keyFile = File(context.filesDir, "adb/private.key")
            val certFile = File(context.filesDir, "adb/cert.pem")
            keyFile.parentFile?.mkdirs()

            if (keyFile.exists() && certFile.exists()) {
                privateKey = KeyFactory.getInstance("RSA").generatePrivate(
                    PKCS8EncodedKeySpec(keyFile.readBytes()),
                )
                certificate = CertificateFactory.getInstance("X.509")
                    .generateCertificate(certFile.inputStream())
            } else {
                val gen = KeyPairGenerator.getInstance("RSA")
                gen.initialize(2048, SecureRandom.getInstance("SHA1PRNG"))
                val pair = gen.generateKeyPair()
                privateKey = pair.private
                certificate = selfSign(pair.public, pair.private)

                keyFile.writeBytes(privateKey.encoded)
                certFile.writeBytes(certificate.encoded)
            }
        }

        override fun getPrivateKey(): PrivateKey = privateKey
        override fun getCertificate(): Certificate = certificate

        // Shown on the device's "paired devices" list, so name it something a
        // user will recognise later when deciding what to revoke.
        override fun getDeviceName(): String = "CyberNeurova"

        /**
         * Android has no X.509 builder, hence the repackaged AOSP classes.
         * Validity is deliberately long: an expired certificate would break
         * pairing silently, months later, in a way nobody would connect to
         * this code.
         */
        private fun selfSign(
            publicKey: java.security.PublicKey,
            signWith: PrivateKey,
        ): Certificate {
            val from = Date()
            val to = Date(from.time + 10L * 365 * 24 * 60 * 60 * 1000)
            val info = X509CertInfo().apply {
                set(X509CertInfo.VALIDITY, CertificateValidity(from, to))
                set(
                    X509CertInfo.SERIAL_NUMBER,
                    CertificateSerialNumber(SecureRandom().nextInt() and 0x7fffffff),
                )
                set(
                    X509CertInfo.SUBJECT,
                    CertificateSubjectName(X500Name("CN=CyberNeurova")),
                )
                // CertificateIssuerName, NOT CertificateSubjectName. The
                // AOSP X509CertInfo checks the wrapper class per field and
                // rejects the wrong one with "Issuer class type invalid" —
                // which surfaces as a pairing failure, several layers away
                // from the cause.
                set(
                    X509CertInfo.ISSUER,
                    CertificateIssuerName(X500Name("CN=CyberNeurova")),
                )
                set(X509CertInfo.KEY, CertificateX509Key(publicKey))
                set(X509CertInfo.VERSION, CertificateVersion(CertificateVersion.V3))
                set(
                    X509CertInfo.ALGORITHM_ID,
                    CertificateAlgorithmId(
                        AlgorithmId.get(AlgorithmId.sha256WithRSAEncryption_oid.toString()),
                    ),
                )
            }
            return X509CertImpl(info).apply { sign(signWith, "SHA256withRSA") }
        }
    }

    private fun managerOrCreate(): Manager = shared(context)

    /** Whether we have ever paired — the key on disk is the evidence. */
    fun isPaired(): Boolean =
        File(context.filesDir, "adb/private.key").exists() &&
            File(context.filesDir, "adb/cert.pem").exists()

    /**
     * Pairs using the code from Settings.
     *
     * [port] is the **pairing** port shown inside the pairing dialog, which is
     * NOT the port listed on the wireless debugging screen behind it. Getting
     * those two confused is the single most common way this fails, so the UI
     * has to be explicit about which number to read.
     */
    fun pair(port: Int, code: String): Map<String, Any?> = try {
        val ok = managerOrCreate().pair(HOST, port, code)
        mapOf("ok" to ok, "error" to if (ok) null else "Pairing was refused.")
    } catch (t: Throwable) {
        mapOf("ok" to false, "error" to describe(t))
    }

    /**
     * Finds the pairing port over mDNS, so the user does not have to copy it.
     *
     * This exists because transcribing TWO values between apps does not work
     * in practice: switching away from the pairing dialog can close it, and
     * the port changes every time it reopens — so by the time someone has
     * typed the port, the code they memorised may belong to a dead session.
     *
     * Android advertises the pairing service as `_adb-tls-pairing._tcp` while
     * the dialog is open. Browsing for it cuts what the user must carry
     * across to the six digits, which is the part they can actually hold in
     * their head.
     *
     * Blocking; call off the main thread.
     */
    fun discoverPairingPort(timeoutMs: Long): Map<String, Any?> {
        val found = java.util.concurrent.atomic.AtomicInteger(-1)
        val latch = java.util.concurrent.CountDownLatch(1)
        var mdns: AdbMdns? = null
        return try {
            mdns = AdbMdns(context, AdbMdns.SERVICE_TYPE_TLS_PAIRING) { _, port ->
                if (port > 0 && found.compareAndSet(-1, port)) latch.countDown()
            }
            mdns.start()
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            val p = found.get()
            if (p > 0) {
                mapOf("ok" to true, "port" to p, "error" to null)
            } else {
                mapOf(
                    "ok" to false,
                    "port" to -1,
                    "error" to "No pairing dialog is open. In Developer " +
                        "options, tap \"Pair device with pairing code\" and " +
                        "leave it on screen.",
                )
            }
        } catch (t: Throwable) {
            mapOf("ok" to false, "port" to -1, "error" to describe(t))
        } finally {
            try {
                mdns?.stop()
            } catch (_: Throwable) {
                // Stopping a browser that never started is not a failure.
            }
        }
    }

    /**
     * Connects, discovering the port over mDNS.
     *
     * Android gives wireless debugging a **random port** every time it is
     * enabled, so there is nothing worth remembering — `autoConnect` browses
     * for it exactly as `adb` does.
     */
    fun connect(timeoutMs: Long): Map<String, Any?> = try {
        val m = managerOrCreate()
        val ok = m.autoConnect(context, timeoutMs)
        mapOf(
            "ok" to ok,
            "error" to if (ok) null else "Could not reach wireless debugging.",
        )
    } catch (t: AdbPairingRequiredException) {
        mapOf(
            "ok" to false,
            "needsPairing" to true,
            "error" to "Not paired with this device yet.",
        )
    } catch (t: Throwable) {
        mapOf("ok" to false, "error" to describe(t))
    }

    /**
     * What we are connected to, for the UI to state plainly.
     *
     * "Connected" on its own is not reassuring — people want to see WHICH
     * device and at what privilege, especially for something that can install
     * apps without asking.
     */
    fun connectionInfo(): Map<String, Any?> {
        if (!isConnected()) {
            return mapOf("connected" to false, "device" to null, "uid" to null)
        }
        val uid = (exec("id -u", 6_000)["stdout"] as? String)?.trim()
        return mapOf(
            "connected" to true,
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            "androidVersion" to Build.VERSION.RELEASE,
            "uid" to uid?.takeIf { it.isNotEmpty() },
        )
    }

    fun isConnected(): Boolean = try {
        instance?.isConnected == true
    } catch (_: Throwable) {
        false
    }

    fun disconnect() {
        try {
            instance?.disconnect()
        } catch (_: Throwable) {
            // Disconnecting something already gone is the normal case after a
            // reboot, not a failure worth reporting.
        }
    }

    /**
     * Runs [command] through the ADB `shell:` service and returns its output.
     *
     * The shell service carries no exit status, so callers needing one append
     * `; echo $?`. Reporting a fabricated 0 would be worse than admitting we
     * do not know.
     */
    fun exec(command: String, timeoutMs: Long): Map<String, Any?> {
        val m = instance ?: return notConnected("Not connected.")
        return try {
            if (!m.isConnected) return notConnected("Connection dropped.")
            // Raw destination, not openStream(SHELL, command). The typed
            // overload passes each arg as its own argv token, so `id -u`
            // became a request to execute a file literally named "id -u" and
            // came back as "inaccessible or not found". The ADB `shell:`
            // service takes the whole command line as one string.
            val stream = m.openStream("shell:$command")
            val out = StringBuilder()

            // The read happens on its own thread and is joined with a
            // deadline. The obvious loop — check the clock, then read — cannot
            // time out at all: InputStream.read() BLOCKS, so the clock is only
            // consulted after the read has already returned. A command whose
            // stream does not close promptly hung the caller for the whole
            // timeout, which is exactly what "tapped Connect and it just
            // spins" looks like.
            val reader = Thread {
                try {
                    stream.openInputStream().bufferedReader().use { r ->
                        val buf = CharArray(4096)
                        while (true) {
                            val n = r.read(buf)
                            if (n < 0) break
                            synchronized(out) { out.appendRange(buf, 0, n) }
                        }
                    }
                } catch (_: Throwable) {
                    // Stream closed under us; whatever arrived is the answer.
                }
            }
            reader.isDaemon = true
            reader.start()
            reader.join(timeoutMs)

            stream.close()
            mapOf(
                "ok" to true,
                "exitCode" to 0,
                "stdout" to synchronized(out) { out.toString() },
                "stderr" to "",
            )
        } catch (t: Throwable) {
            notConnected(describe(t))
        }
    }

    private fun notConnected(why: String) = mapOf(
        "ok" to false,
        "exitCode" to -1,
        "stdout" to "",
        "stderr" to why,
    )

    /** Something a user can act on, not a stack trace. */
    private fun describe(t: Throwable): String {
        val msg = t.message?.takeIf { it.isNotBlank() }
        return when {
            t is java.net.ConnectException ->
                "Nothing is listening. Is wireless debugging switched on?"
            t is AdbPairingRequiredException ->
                "Not paired with this device yet."
            msg != null -> msg
            else -> t.javaClass.simpleName
        }
    }

    companion object {
        /**
         * One manager for the whole process.
         *
         * It used to hang off the Activity, so every time MainActivity was
         * destroyed and recreated — a rotation, a back-and-forward, coming
         * back from Settings — the live AdbConnection went with it and the
         * user saw "not connected" as though the pairing had been lost. It
         * had not: the trusted key is on disk and survives. Only the socket
         * needed re-establishing, and only because we were throwing it away.
         */
        @Volatile
        private var instance: Manager? = null

        private fun shared(context: Context): Manager =
            instance ?: synchronized(this) {
                instance ?: Manager(context.applicationContext)
                    .also { instance = it }
            }

        /** The phone talks to itself; this never leaves the device. */
        private const val HOST = "127.0.0.1"

        /** mDNS discovery needs a moment; adb itself waits about this long. */
        const val DEFAULT_TIMEOUT_MS = 10_000L

        @Suppress("unused")
        private val UNUSED = TimeUnit.MILLISECONDS
    }
}
