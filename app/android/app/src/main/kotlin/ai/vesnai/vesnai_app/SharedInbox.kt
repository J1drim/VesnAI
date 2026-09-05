package ai.vesnai.vesnai_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/** Each share has its own immutable ready manifest; listing never consumes it. */
class SharedInbox(private val context: Context) {
    private val root get() = File(context.filesDir, "shared_inbox").apply { mkdirs() }

    fun receive(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return false
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: ""
        require(text.length <= 1_000_000) { "Shared text exceeds 1 MB" }
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java) ?: arrayListOf()
        } else {
            listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
        }
        require(uris.size <= 10) { "Share at most ten files" }
        require(text.isNotBlank() || uris.isNotEmpty()) { "Nothing to share" }
        val id = UUID.randomUUID().toString()
        val folder = File(root, id).apply { mkdirs() }
        try {
            var total = 0L
            val files = JSONArray()
            uris.forEachIndexed { index, uri ->
                require(uri.scheme == "content" && uri.authority != "${context.packageName}.fileprovider") {
                    "Only externally granted content URIs are accepted"
                }
                var name = "attachment.bin"
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) name = cursor.getString(0)?.take(240) ?: name
                }
                val suffix = Regex("\\.[a-z0-9]{1,10}$").find(name.lowercase())?.value ?: ".bin"
                val file = File(folder, "$index$suffix")
                val input = context.contentResolver.openInputStream(uri) ?: error("Shared file is unavailable")
                input.use { source -> FileOutputStream(file).use { output ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= 50L * 1024 * 1024) { "Shared files exceed 50 MB" }
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                } }
                files.put(JSONObject().put("name", name).put("path", file.absolutePath))
            }
            val payload = JSONObject().put("id", id).put("text", text)
                .put("title", intent.getStringExtra(Intent.EXTRA_SUBJECT)?.take(240) ?: "")
                .put("files", files)
            val staged = File(folder, "ready.tmp")
            FileOutputStream(staged).use { output ->
                output.write(payload.toString().toByteArray(Charsets.UTF_8)); output.fd.sync()
            }
            check(staged.renameTo(File(folder, "ready.json"))) { "Could not save shared content" }
            return true
        } catch (error: Exception) {
            folder.deleteRecursively() // only this incomplete intake, never a ready share
            throw error
        }
    }

    fun list(): String {
        val items = JSONArray()
        root.listFiles()?.sortedBy { it.name }?.forEach { folder ->
            val ready = File(folder, "ready.json")
            if (ready.isFile) items.put(JSONObject(ready.readText()))
        }
        return items.toString()
    }

    fun acknowledge(id: String) {
        require(Regex("[a-fA-F0-9-]{36}").matches(id)) { "Invalid share identifier" }
        val folder = File(root, id)
        check(!folder.exists() || folder.deleteRecursively()) { "Could not clear imported share" }
    }
}
