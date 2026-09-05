package ai.vesnai.vesnai_app

import android.content.Intent
import android.net.Uri
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.ByteArrayInputStream
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class SharedInboxTest {
    @Test fun persistsGrantedMediaUntilExplicitAcknowledgement() {
        val context = RuntimeEnvironment.getApplication()
        val uri = Uri.parse("content://test.provider/shared.pdf")
        shadowOf(context.contentResolver).registerInputStream(uri, ByteArrayInputStream(byteArrayOf(1, 2, 3)))
        val inbox = SharedInbox(context)
        val intent = Intent(Intent.ACTION_SEND).setType("application/pdf")
            .putExtra(Intent.EXTRA_TEXT, "https://example.com").putExtra(Intent.EXTRA_STREAM, uri)
        assertTrue(inbox.receive(intent))
        val item = JSONArray(inbox.list()).getJSONObject(0)
        val file = File(item.getJSONArray("files").getJSONObject(0).getString("path"))
        assertArrayEquals(byteArrayOf(1, 2, 3), file.readBytes())
        assertEquals(1, JSONArray(SharedInbox(context).list()).length())
        inbox.acknowledge(item.getString("id"))
        assertEquals(0, JSONArray(inbox.list()).length())
        assertFalse(file.exists())
    }

    @Test fun rejectsPrivateFileUrisAndTraversalAcknowledgements() {
        val context = RuntimeEnvironment.getApplication()
        val inbox = SharedInbox(context)
        val intent = Intent(Intent.ACTION_SEND).setType("application/pdf")
            .putExtra(Intent.EXTRA_STREAM, Uri.parse("file:///data/private/secret"))
        assertThrows(IllegalArgumentException::class.java) { inbox.receive(intent) }
        assertThrows(IllegalArgumentException::class.java) { inbox.acknowledge("../") }
        assertEquals(0, JSONArray(inbox.list()).length())
    }
}
