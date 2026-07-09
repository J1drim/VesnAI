// JUnit/Robolectric test for the Android widget's shared-storage parsing.
// Runs on Android CI (Gradle), not in `flutter test`.

package ai.vesnai.vesnai_app.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class WidgetStoreTest {
    @Test
    fun parsesRecentsFromSnapshot() {
        val raw = """
            {"version":1,"recents":[
              {"title":"Idea","type":"Idea","generated":false},
              {"title":"AI image","type":"GeneratedImage","generated":true}
            ]}
        """.trimIndent()
        val recents = WidgetStore.parseRecents(raw)
        assertEquals(2, recents.size)
        assertEquals("Idea", recents[0].title)
        assertTrue(recents[1].generated)
    }

    @Test
    fun honorsLimit() {
        val raw = """{"version":1,"recents":[
            {"title":"a"},{"title":"b"},{"title":"c"},{"title":"d"}]}"""
        assertEquals(2, WidgetStore.parseRecents(raw, limit = 2).size)
    }

    @Test
    fun defaultLimitIsTen() {
        val raw = """{"version":1,"recents":[
            {"title":"a"},{"title":"b"},{"title":"c"},{"title":"d"},
            {"title":"e"},{"title":"f"},{"title":"g"},{"title":"h"},
            {"title":"i"},{"title":"j"},{"title":"k"}]}"""
        assertEquals(10, WidgetStore.parseRecents(raw).size)
    }

    @Test
    fun emptyOnMissingRecents() {
        assertTrue(WidgetStore.parseRecents("{\"version\":1}").isEmpty())
    }

    @Test
    fun parsesChatRecentsFromV2Snapshot() {
        val raw = """
            {"version":2,"recents":[],"chatRecents":[
              {"id":"sess-1","title":"Trip","updated":"2026-01-01"}
            ]}
        """.trimIndent()
        val chats = WidgetStore.parseChatRecents(raw)
        assertEquals(1, chats.size)
        assertEquals("sess-1", chats[0].id)
        assertEquals("Trip", chats[0].title)
    }

    @Test
    fun chatRecentsEmptyOnV1Snapshot() {
        assertTrue(WidgetStore.parseChatRecents("{\"version\":1,\"recents\":[]}").isEmpty())
    }

    @Test
    fun parseRecentsSafeReturnsEmptyOnMalformedJson() {
        assertTrue(WidgetStore.parseRecentsSafe("not-json").isEmpty())
    }

    @Test
    fun parseChatRecentsSafeReturnsEmptyOnMalformedJson() {
        assertTrue(WidgetStore.parseChatRecentsSafe("{broken").isEmpty())
    }

    @Test
    fun invalidateSnapshotCache_clearsParsedCache() {
        WidgetStore.primeCacheForTest("cached", WidgetStore.SnapshotData())
        assertTrue(WidgetStore.hasCachedSnapshot())
        WidgetStore.invalidateSnapshotCache()
        assertFalse(WidgetStore.hasCachedSnapshot())
    }
}
