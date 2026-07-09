package ai.vesnai.vesnai_app.widget

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState

// Switch the home widget between Notes and Chat tabs without opening the app.
class WidgetTabAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val appContext = context.applicationContext
        val tab = parameters[TabKey] ?: TAB_NOTES
        val current = VesnaiGlanceWidget.instance.getAppWidgetState<Preferences>(context, glanceId)
        if ((current[TAB_KEY] ?: TAB_NOTES) == tab) return

        updateAppWidgetState(context, glanceId) { prefs ->
            prefs[TAB_KEY] = tab
        }
        WidgetUpdateCoordinator.refreshTab(appContext, glanceId)
    }

    companion object {
        const val TAB_NOTES = "notes"
        const val TAB_CHAT = "chat"
        val TAB_KEY = stringPreferencesKey("widget_tab")
        val TabKey = ActionParameters.Key<String>("tab")
    }
}
