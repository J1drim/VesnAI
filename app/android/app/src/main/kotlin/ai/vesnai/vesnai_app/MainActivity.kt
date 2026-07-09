package ai.vesnai.vesnai_app

import ai.vesnai.vesnai_app.widget.WidgetStore
import ai.vesnai.vesnai_app.widget.WidgetUpdateCoordinator
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/// Bridges the Flutter `vesnai/widgets` channel to the shared prefs the Glance
/// home-screen widget reads (see widget/VesnaiGlanceWidget.kt). Writing a
/// snapshot also refreshes the live widget, and widget taps are forwarded back
/// to Flutter as `widgetAction` calls for deep-linking.
class MainActivity : FlutterActivity() {
    private val widgetChannelName = "vesnai/widgets"
    private val volumeChannelName = "vesnai/media_volume"
    private val prefsName = "vesnai_widget"
    private val keySnapshot = "widget_snapshot"
    private val keyCaptures = "quick_captures"
    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: Map<String, String?>? = null
    private var lastWrittenSnapshot: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val widgetCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
        widgetChannel = widgetCh
        widgetCh.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            when (call.method) {
                "writeSnapshot" -> {
                    val encoded = call.arguments as String
                    if (encoded == lastWrittenSnapshot ||
                        encoded == prefs.getString(keySnapshot, null)
                    ) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    prefs.edit().putString(keySnapshot, encoded).apply()
                    lastWrittenSnapshot = encoded
                    WidgetStore.invalidateSnapshotCache()
                    WidgetUpdateCoordinator.scheduleDataRefresh(this@MainActivity)
                    result.success(null)
                }
                "readSnapshot" -> result.success(prefs.getString(keySnapshot, null))
                "drainQuickCaptures" -> {
                    val raw = prefs.getString(keyCaptures, null)
                    prefs.edit().remove(keyCaptures).apply()
                    result.success(raw)
                }
                "pushQuickCapture" -> {
                    val arr = JSONArray(prefs.getString(keyCaptures, "[]"))
                    arr.put(JSONObject(call.arguments as String))
                    prefs.edit().putString(keyCaptures, arr.toString()).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMusicVolume" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(if (max > 0) cur.toDouble() / max else 0.0)
                    }
                    else -> result.notImplemented()
                }
            }
        handleWidgetIntent(intent)
        drainPendingWidgetAction()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
    }

    /// Forward a widget tap (open note / chat / new note) to Flutter once.
    private fun handleWidgetIntent(intent: Intent?) {
        val action = intent?.getStringExtra("vesnai_action")
        if (action == null) {
            drainPendingWidgetAction()
            return
        }
        if (!isTrustedWidgetIntent(intent)) {
            clearWidgetIntentExtras(intent)
            return
        }
        val notePath = intent.getStringExtra("vesnai_note_path")
        if (action == "open_note" && !isValidNotePath(notePath)) {
            clearWidgetIntentExtras(intent)
            return
        }
        val payload = mapOf(
            "action" to action,
            "path" to notePath,
            "sessionId" to intent.getStringExtra("vesnai_chat_id"),
        )
        if (widgetChannel == null) {
            pendingWidgetAction = payload
            return
        }
        forwardWidgetAction(payload, intent)
    }

    private fun forwardWidgetAction(payload: Map<String, String?>, intent: Intent?) {
        val channel = widgetChannel
        if (channel == null) {
            pendingWidgetAction = payload
            return
        }
        channel.invokeMethod(
            "widgetAction",
            payload,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    clearWidgetIntentExtras(intent)
                    pendingWidgetAction = null
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    pendingWidgetAction = payload
                }

                override fun notImplemented() {
                    pendingWidgetAction = payload
                }
            },
        )
    }

    private fun drainPendingWidgetAction() {
        val pending = pendingWidgetAction ?: return
        forwardWidgetAction(pending, null)
    }

    private fun clearWidgetIntentExtras(intent: Intent?) {
        intent?.removeExtra("vesnai_action")
        intent?.removeExtra("vesnai_note_path")
        intent?.removeExtra("vesnai_chat_id")
    }

    private fun isTrustedWidgetIntent(intent: Intent): Boolean {
        val component = intent.component
        if (component != null && component.packageName != packageName) {
            return false
        }
        return intent.getStringExtra("vesnai_action") != null
    }

    private fun isValidNotePath(path: String?): Boolean {
        if (path.isNullOrBlank()) return false
        if (path.contains("..") || path.startsWith("/") || path.startsWith("\\")) {
            return false
        }
        if (!path.endsWith(".md")) return false
        val base = path.substringAfterLast('/')
        if (base == "index.md" || base == "log.md") return false
        if (path.startsWith("memory/")) return false
        return true
    }
}
