// VesnAI Android home-screen widget (Jetpack Glance): Notes | Chat tabs,
// scrollable recents, and a + button to add a note or start a chat in the app.

package ai.vesnai.vesnai_app.widget

import android.content.Context
import android.content.Intent
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.datastore.preferences.core.Preferences
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.Text
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.ColorFilter
import androidx.glance.layout.size
import ai.vesnai.vesnai_app.MainActivity
import org.json.JSONObject

object WidgetStore {
    private const val PREFS = "vesnai_widget"
    private const val KEY_SNAPSHOT = "widget_snapshot"

    @Volatile
    private var cachedSnapshotRaw: String? = null

    @Volatile
    private var cachedSnapshotData: SnapshotData? = null

    data class Note(val title: String, val type: String, val generated: Boolean, val path: String)
    data class Chat(val id: String, val title: String, val updated: String)

    data class SnapshotData(
        val notes: List<Note> = emptyList(),
        val chats: List<Chat> = emptyList(),
        val parseError: Boolean = false,
    )

    fun loadSnapshot(context: Context, limit: Int = 10): SnapshotData {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT, null) ?: return SnapshotData()
        if (raw == cachedSnapshotRaw && cachedSnapshotData != null) {
            return cachedSnapshotData!!
        }
        val parsed = try {
            SnapshotData(
                notes = parseRecents(raw, limit),
                chats = parseChatRecents(raw, limit),
            )
        } catch (_: Exception) {
            SnapshotData(parseError = true)
        }
        cachedSnapshotRaw = raw
        cachedSnapshotData = parsed
        return parsed
    }

    fun invalidateSnapshotCache() {
        cachedSnapshotRaw = null
        cachedSnapshotData = null
    }

    internal fun primeCacheForTest(raw: String, data: SnapshotData) {
        cachedSnapshotRaw = raw
        cachedSnapshotData = data
    }

    internal fun hasCachedSnapshot(): Boolean = cachedSnapshotData != null

    fun parseRecentsSafe(raw: String, limit: Int = 10): List<Note> =
        try {
            parseRecents(raw, limit)
        } catch (_: Exception) {
            emptyList()
        }

    fun parseChatRecentsSafe(raw: String, limit: Int = 10): List<Chat> =
        try {
            parseChatRecents(raw, limit)
        } catch (_: Exception) {
            emptyList()
        }

    fun parseRecents(raw: String, limit: Int = 10): List<Note> {
        val arr = JSONObject(raw).optJSONArray("recents") ?: return emptyList()
        val out = ArrayList<Note>()
        for (i in 0 until minOf(arr.length(), limit)) {
            val o = arr.getJSONObject(i)
            out.add(
                Note(
                    o.optString("title"),
                    o.optString("type", "Note"),
                    o.optBoolean("generated"),
                    o.optString("path"),
                )
            )
        }
        return out
    }

    fun parseChatRecents(raw: String, limit: Int = 10): List<Chat> {
        val arr = JSONObject(raw).optJSONArray("chatRecents") ?: return emptyList()
        val out = ArrayList<Chat>()
        for (i in 0 until minOf(arr.length(), limit)) {
            val o = arr.getJSONObject(i)
            out.add(
                Chat(
                    o.optString("id"),
                    o.optString("title", "New chat"),
                    o.optString("updated"),
                )
            )
        }
        return out
    }
}

private fun launchIntent(
    context: Context,
    action: String,
    notePath: String? = null,
    chatId: String? = null,
): Intent {
    return Intent(context, MainActivity::class.java).apply {
        setPackage(context.packageName)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        putExtra("vesnai_action", action)
        if (notePath != null) putExtra("vesnai_note_path", notePath)
        if (chatId != null) putExtra("vesnai_chat_id", chatId)
    }
}

private fun tabPill(active: Boolean, tabValue: String): GlanceModifier {
    var mod = GlanceModifier
        .padding(horizontal = 12.dp, vertical = 6.dp)
        .cornerRadius(16.dp)
    mod = if (active) {
        mod.background(VesnaiWidgetColors.primaryContainer)
    } else {
        mod.background(VesnaiWidgetColors.surface)
    }
    return mod.clickable(
        actionRunCallback<WidgetTabAction>(
            actionParametersOf(WidgetTabAction.TabKey to tabValue),
        )
    )
}

private fun noteRowBackground(generated: Boolean) =
    if (generated) VesnaiWidgetColors.generatedTint else VesnaiWidgetColors.surfaceContainerLow

class VesnaiGlanceWidget : GlanceAppWidget() {
    override val stateDefinition = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetStore.loadSnapshot(context)
        val notes = snapshot.notes
        val chats = snapshot.chats
        provideContent {
            val prefs = currentState<Preferences>()
            val tab = prefs[WidgetTabAction.TAB_KEY] ?: WidgetTabAction.TAB_NOTES
            Column(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(VesnaiWidgetColors.surface)
                    .padding(12.dp)
            ) {
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("VesnAI", style = VesnaiWidgetTheme.masthead)
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = tabPill(
                            tab == WidgetTabAction.TAB_NOTES,
                            WidgetTabAction.TAB_NOTES,
                        ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "Notes",
                            style = if (tab == WidgetTabAction.TAB_NOTES) {
                                VesnaiWidgetTheme.tabActive
                            } else {
                                VesnaiWidgetTheme.tabInactive
                            },
                        )
                    }
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Box(
                        modifier = tabPill(
                            tab == WidgetTabAction.TAB_CHAT,
                            WidgetTabAction.TAB_CHAT,
                        ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "Chat",
                            style = if (tab == WidgetTabAction.TAB_CHAT) {
                                VesnaiWidgetTheme.tabActive
                            } else {
                                VesnaiWidgetTheme.tabInactive
                            },
                        )
                    }
                    Spacer(modifier = GlanceModifier.width(8.dp))
                    val addAction = if (tab == WidgetTabAction.TAB_CHAT) "new_chat" else "new_note"
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(20.dp)
                            .background(VesnaiWidgetColors.primary)
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                            .clickable(actionStartActivity(launchIntent(context, addAction))),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("+", style = VesnaiWidgetTheme.addButton)
                    }
                }
                Spacer(modifier = GlanceModifier.height(8.dp))
                when {
                    snapshot.parseError -> {
                        Text(
                            "Open VesnAI to refresh",
                            style = VesnaiWidgetTheme.emptyState,
                            modifier = GlanceModifier
                                .defaultWeight()
                                .fillMaxWidth()
                                .clickable(
                                    actionStartActivity(launchIntent(context, "new_note")),
                                ),
                        )
                    }
                    tab == WidgetTabAction.TAB_CHAT && chats.isEmpty() -> {
                        Text(
                            "No chats yet — tap + to start",
                            style = VesnaiWidgetTheme.emptyState,
                            modifier = GlanceModifier
                                .defaultWeight()
                                .fillMaxWidth()
                                .clickable(
                                    actionStartActivity(launchIntent(context, "new_chat")),
                                ),
                        )
                    }
                    tab == WidgetTabAction.TAB_CHAT -> {
                        LazyColumn(
                            modifier = GlanceModifier
                                .defaultWeight()
                                .fillMaxWidth(),
                        ) {
                            items(
                                items = chats,
                                itemId = { chat -> chat.id.hashCode().toLong() },
                            ) { chat ->
                                Row(
                                    modifier = GlanceModifier
                                        .fillMaxWidth()
                                        .padding(vertical = 4.dp)
                                        .cornerRadius(12.dp)
                                        .background(VesnaiWidgetColors.surfaceContainerLow)
                                        .padding(10.dp)
                                        .clickable(
                                            actionStartActivity(
                                                launchIntent(
                                                    context,
                                                    "open_chat",
                                                    chatId = chat.id,
                                                )
                                            )
                                        ),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Box(
                                        modifier = GlanceModifier
                                            .width(4.dp)
                                            .height(36.dp)
                                            .background(VesnaiWidgetColors.primaryContainer),
                                    ) {}
                                    Spacer(modifier = GlanceModifier.width(10.dp))
                                    Column(modifier = GlanceModifier.defaultWeight()) {
                                        Text(
                                            chat.title.ifEmpty { "New chat" },
                                            style = VesnaiWidgetTheme.rowTitle,
                                        )
                                        if (chat.updated.isNotEmpty()) {
                                            Text(chat.updated, style = VesnaiWidgetTheme.rowMeta)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    tab == WidgetTabAction.TAB_NOTES && notes.isEmpty() -> {
                        Text(
                            "No notes yet — tap + to capture a thought",
                            style = VesnaiWidgetTheme.emptyState,
                            modifier = GlanceModifier
                                .defaultWeight()
                                .fillMaxWidth()
                                .clickable(
                                    actionStartActivity(launchIntent(context, "new_note")),
                                ),
                        )
                    }
                    tab == WidgetTabAction.TAB_NOTES -> {
                        LazyColumn(
                            modifier = GlanceModifier
                                .defaultWeight()
                                .fillMaxWidth(),
                        ) {
                            items(
                                items = notes,
                                itemId = { note -> note.path.hashCode().toLong() },
                            ) { note ->
                                Row(
                                    modifier = GlanceModifier
                                        .fillMaxWidth()
                                        .padding(vertical = 4.dp)
                                        .cornerRadius(12.dp)
                                        .background(noteRowBackground(note.generated))
                                        .padding(10.dp)
                                        .clickable(
                                            actionStartActivity(
                                                launchIntent(context, "open_note", note.path)
                                            )
                                        ),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Box(
                                        modifier = GlanceModifier
                                            .width(32.dp)
                                            .height(32.dp)
                                            .cornerRadius(16.dp)
                                            .background(NoteTypeWidgetStyle.tint(note.type)),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Image(
                                            provider = ImageProvider(
                                                NoteTypeWidgetStyle.iconRes(note.type),
                                            ),
                                            contentDescription = note.type,
                                            modifier = GlanceModifier.size(18.dp),
                                            colorFilter = ColorFilter.tint(
                                                NoteTypeWidgetStyle.colorProvider(note.type),
                                            ),
                                        )
                                    }
                                    Spacer(modifier = GlanceModifier.width(10.dp))
                                    Column(modifier = GlanceModifier.defaultWeight()) {
                                        Text(
                                            note.title.ifEmpty { "(untitled)" },
                                            style = VesnaiWidgetTheme.rowTitle,
                                            maxLines = 1,
                                        )
                                        Text(note.type, style = VesnaiWidgetTheme.rowMeta)
                                    }
                                    if (note.generated) {
                                        Text("AI", style = VesnaiWidgetTheme.aiLabel)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    companion object {
        val instance = VesnaiGlanceWidget()
    }
}

class VesnaiGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = VesnaiGlanceWidget.instance
}
