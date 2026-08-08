package ai.cyberneurova.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * What is on this network, by asking it.
 *
 * ## Why this is native and not Dart
 *
 * mDNS needs multicast on 224.0.0.251:5353, and Dart's `RawDatagramSocket`
 * cannot join a multicast group on Android with the socket options it exposes —
 * which is why `MDNS_DISCOVERY` has been in the MISSING list since the
 * capability set was written. `NsdManager` is the platform's own answer and
 * handles the multicast lock, the wake lock and the wire format.
 *
 * ## Why it matters more here than on a laptop
 *
 * A scan tells you a port is open. mDNS tells you the box calls itself
 * "living-room-tv" and speaks `_googlecast._tcp`. On someone's own network that
 * is the difference between a list of IPs and a list of things — and it is only
 * possible from the phone, because a server-side container has no route to it.
 *
 * ## The trap
 *
 * `resolveService` is single-flight. Fire two and the second fails with
 * `FAILURE_ALREADY_ACTIVE`, which on a busy network silently loses most of what
 * discovery found. So resolution is queued through one worker, and browsing
 * continues underneath it.
 */
object NsdDiscovery {

    /**
     * Service types worth asking about by default.
     *
     * Chosen for what is actually on a home or office network rather than for
     * completeness: every extra type is another browse running for the whole
     * timeout, and the long tail returns nothing on most networks.
     */
    val defaultTypes = listOf(
        "_http._tcp",
        "_https._tcp",
        "_ssh._tcp",
        "_sftp-ssh._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp",
        "_printer._tcp",
        "_ipp._tcp",
        "_googlecast._tcp",
        "_airplay._tcp",
        "_raop._tcp",
        "_workstation._tcp",
        "_device-info._tcp",
        "_adb-tls-connect._tcp",
    )

    /**
     * Browses [types] for [timeoutMs] and returns everything resolved.
     *
     * Blocking — callers run it off the main thread. Never throws: a network
     * with nothing on it is an ordinary answer, and so is a device that refuses
     * multicast.
     */
    fun discover(
        context: Context,
        timeoutMs: Long,
        types: List<String> = defaultTypes,
    ): List<Map<String, Any?>> {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
            ?: return emptyList()

        // Keyed by type+name: the same printer answers on several types and
        // should appear once per service, not once per browse.
        val found = ConcurrentHashMap<String, Map<String, Any?>>()
        val pending = LinkedBlockingQueue<NsdServiceInfo>()
        val listeners = mutableListOf<Pair<String, NsdManager.DiscoveryListener>>()

        val deadline = System.currentTimeMillis() + timeoutMs
        val resolverDone = CountDownLatch(1)

        // One resolver thread. resolveService is single-flight; firing them in
        // parallel means every one after the first fails with
        // FAILURE_ALREADY_ACTIVE and the network looks emptier than it is.
        val resolver = Thread {
            while (System.currentTimeMillis() < deadline) {
                val info = pending.poll(200, TimeUnit.MILLISECONDS) ?: continue
                val latch = CountDownLatch(1)
                try {
                    @Suppress("DEPRECATION")
                    nsd.resolveService(
                        info,
                        object : NsdManager.ResolveListener {
                            override fun onResolveFailed(si: NsdServiceInfo, code: Int) {
                                // A service that vanished between browse and
                                // resolve is normal on a phone changing cells.
                                latch.countDown()
                            }

                            override fun onServiceResolved(si: NsdServiceInfo) {
                                val host = si.host?.hostAddress
                                if (host != null) {
                                    found["${si.serviceType}|${si.serviceName}"] = mapOf(
                                        "name" to si.serviceName,
                                        "type" to si.serviceType.trim('.'),
                                        "host" to host,
                                        "port" to si.port,
                                    )
                                }
                                latch.countDown()
                            }
                        },
                    )
                } catch (_: Throwable) {
                    latch.countDown()
                }
                // Bounded: a resolve that never calls back must not hold the
                // queue for the rest of the run.
                latch.await(3, TimeUnit.SECONDS)
            }
            resolverDone.countDown()
        }
        resolver.isDaemon = true
        resolver.start()

        for (type in types) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(t: String) {}
                override fun onDiscoveryStopped(t: String) {}
                override fun onStartDiscoveryFailed(t: String, code: Int) {}
                override fun onStopDiscoveryFailed(t: String, code: Int) {}
                override fun onServiceFound(si: NsdServiceInfo) {
                    pending.offer(si)
                }

                override fun onServiceLost(si: NsdServiceInfo) {
                    found.remove("${si.serviceType}|${si.serviceName}")
                }
            }
            try {
                nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
                listeners.add(type to listener)
            } catch (_: Throwable) {
                // One unsupported type must not stop the rest.
            }
        }

        try {
            Thread.sleep(timeoutMs)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }

        for ((_, listener) in listeners) {
            try {
                nsd.stopServiceDiscovery(listener)
            } catch (_: Throwable) {
                // Already stopped. Nothing to do and nothing worth failing on.
            }
        }
        resolverDone.await(4, TimeUnit.SECONDS)

        return found.values.sortedWith(
            compareBy({ it["host"] as? String ?: "" }, { it["name"] as? String ?: "" }),
        )
    }
}
