package com.guardianlink.app

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Browsing history monitor (browsers only).
 *
 * Reads the address bar of supported browser apps when its content changes,
 * queues visited addresses on the device and uploads them to the backend
 * (POST /api/browsing/log) using the login token the Flutter app stored.
 *
 * Only the browsers in URL_BAR_IDS are monitored (the same list is set as
 * packageNames in res/xml/browser_accessibility_config.xml, so Android does
 * not even send events from other apps). Text being typed is ignored.
 */
class BrowserMonitorService : AccessibilityService() {

    private var lastUrl: String? = null
    private var lastUrlAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        val ids = URL_BAR_IDS[pkg] ?: return
        val root = rootInActiveWindow ?: return
        try {
            val raw = findUrl(root, pkg, ids) ?: return
            val url = normalize(raw) ?: return
            val now = System.currentTimeMillis()
            if (url == lastUrl && now - lastUrlAt < DEDUP_MS) return
            lastUrl = url
            lastUrlAt = now
            enqueue(applicationContext, url, pkg, now)
        } catch (e: Exception) {
            // Never crash the accessibility service.
        }
    }

    override fun onInterrupt() {}

    private fun findUrl(root: AccessibilityNodeInfo, pkg: String, ids: List<String>): String? {
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId("$pkg:id/$id") ?: continue
            for (node in nodes) {
                // While the address bar is focused the child is typing, not visiting.
                if (node.isFocused) continue
                val text = node.text?.toString()?.trim()
                if (!text.isNullOrEmpty()) return text
            }
        }
        return null
    }

    /** Returns a web address, or null for hints / search text / internal pages. */
    private fun normalize(text: String): String? {
        if (text.length > 2048) return null
        if (text.any { it.isWhitespace() }) return null // placeholder hint or search words
        val lower = text.lowercase(Locale.ROOT)
        if (lower.startsWith("chrome://") || lower.startsWith("about:") ||
            lower.startsWith("edge://") || lower.startsWith("brave://") ||
            lower.startsWith("file://") || lower.startsWith("content://")
        ) return null
        if (!lower.startsWith("http://") && !lower.startsWith("https://") && !lower.contains('.')) return null
        return text
    }

    companion object {
        private const val DEDUP_MS = 60_000L
        private const val PREFS = "guardianlink_browsing"
        private const val KEY_QUEUE = "queue"
        private const val MAX_QUEUE = 500
        private const val BATCH = 200

        // Flutter's shared_preferences file and key prefix
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_TOKEN = "flutter.auth_token"
        private const val KEY_BASE_URL = "flutter.api_base_url"

        private val executor = Executors.newSingleThreadExecutor()

        /** Browser package -> address bar view ids. Keep in sync with the XML config. */
        val URL_BAR_IDS: Map<String, List<String>> = mapOf(
            "com.android.chrome" to listOf("url_bar"),
            "com.chrome.beta" to listOf("url_bar"),
            "com.microsoft.emmx" to listOf("url_bar"),
            "com.brave.browser" to listOf("url_bar"),
            "com.kiwibrowser.browser" to listOf("url_bar"),
            "com.vivaldi.browser" to listOf("url_bar"),
            "com.opera.browser" to listOf("url_field"),
            "com.opera.mini.native" to listOf("url_field"),
            "org.mozilla.firefox" to listOf("mozac_browser_toolbar_url_view", "url_bar_title"),
            "com.sec.android.app.sbrowser" to listOf("location_bar_edit_text", "custom_tab_toolbar_url_bar_text"),
            "com.duckduckgo.mobile.android" to listOf("omnibarTextInput"),
        )

        fun isEnabled(context: Context): Boolean {
            val expected = ComponentName(context, BrowserMonitorService::class.java)
            val enabled = Settings.Secure.getString(
                context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val splitter = TextUtils.SimpleStringSplitter(':')
            splitter.setString(enabled)
            for (entry in splitter) {
                if (ComponentName.unflattenFromString(entry) == expected) return true
            }
            return false
        }

        fun flushAsync(context: Context) {
            executor.execute { upload(context) }
        }

        private fun enqueue(context: Context, url: String, browser: String, timeMillis: Long) {
            executor.execute {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
                queue.put(JSONObject().apply {
                    put("url", url)
                    put("browser", browser)
                    put("visited_at", iso(timeMillis))
                })
                // Keep only the newest MAX_QUEUE entries while offline.
                val trimmed = JSONArray()
                val start = maxOf(0, queue.length() - MAX_QUEUE)
                for (i in start until queue.length()) trimmed.put(queue.get(i))
                prefs.edit().putString(KEY_QUEUE, trimmed.toString()).apply()
                upload(context)
            }
        }

        /** Runs on the executor thread only. */
        private fun upload(context: Context) {
            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val token = flutterPrefs.getString(KEY_TOKEN, null) ?: return
            val baseUrl = flutterPrefs.getString(KEY_BASE_URL, null) ?: return

            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            if (queue.length() == 0) return

            val count = minOf(BATCH, queue.length())
            val batch = JSONArray()
            for (i in 0 until count) batch.put(queue.get(i))

            var connection: HttpURLConnection? = null
            try {
                connection = (URL("${baseUrl.trimEnd('/')}/api/browsing/log").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 10_000
                    readTimeout = 15_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                }
                connection.outputStream.use {
                    it.write(JSONObject().put("visits", batch).toString().toByteArray(Charsets.UTF_8))
                }
                val code = connection.responseCode
                when {
                    code in 200..299 -> removeFirst(prefs, count)
                    // Not a child account / logged out: these visits can't be delivered.
                    code == 401 || code == 403 -> prefs.edit().putString(KEY_QUEUE, "[]").apply()
                    // Anything else (offline, server error): keep and retry on next visit.
                }
            } catch (e: Exception) {
                // Offline: keep the queue.
            } finally {
                connection?.disconnect()
            }
        }

        private fun removeFirst(prefs: android.content.SharedPreferences, count: Int) {
            val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            val rest = JSONArray()
            for (i in count until queue.length()) rest.put(queue.get(i))
            prefs.edit().putString(KEY_QUEUE, rest.toString()).apply()
        }

        private fun iso(timeMillis: Long): String {
            val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            format.timeZone = TimeZone.getTimeZone("UTC")
            return format.format(Date(timeMillis))
        }
    }
}
