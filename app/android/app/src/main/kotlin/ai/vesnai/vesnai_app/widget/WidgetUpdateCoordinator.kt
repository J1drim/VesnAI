package ai.vesnai.vesnai_app.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Serializes Glance widget updates so tab switches and snapshot refreshes never stack.
 */
object WidgetUpdateCoordinator {
    private val scope = CoroutineScope(Dispatchers.Default)
    private val mutex = Mutex()
    private var dataRefreshJob: Job? = null
    private var tabRefreshInFlight = false

    fun scheduleDataRefresh(context: Context) {
        dataRefreshJob?.cancel()
        dataRefreshJob = scope.launch {
            delay(500)
            mutex.withLock {
                if (tabRefreshInFlight) {
                    scheduleDataRefreshLocked(context)
                    return@launch
                }
                VesnaiGlanceWidget.instance.updateAll(context)
            }
        }
    }

    fun refreshTab(context: Context, glanceId: GlanceId) {
        dataRefreshJob?.cancel()
        dataRefreshJob = null
        scope.launch {
            mutex.withLock {
                tabRefreshInFlight = true
                try {
                    VesnaiGlanceWidget.instance.update(context, glanceId)
                } finally {
                    tabRefreshInFlight = false
                }
            }
        }
    }

    private fun scheduleDataRefreshLocked(context: Context) {
        dataRefreshJob?.cancel()
        dataRefreshJob = scope.launch {
            delay(500)
            mutex.withLock {
                if (!tabRefreshInFlight) {
                    VesnaiGlanceWidget.instance.updateAll(context)
                }
            }
        }
    }
}

