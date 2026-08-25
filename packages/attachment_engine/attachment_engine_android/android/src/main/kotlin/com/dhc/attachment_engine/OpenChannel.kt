package com.dhc.attachment_engine

import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Replaces `open_filex`. Uses `Intent.ACTION_VIEW` with a FileProvider
 * content URI, inferred MIME type, and `grantUriPermission`. Implements
 * the Pigeon-generated [OpenHostApi].
 */
class OpenChannel(private val context: Context) : OpenHostApi {
    fun register(messenger: BinaryMessenger) {
        OpenHostApi.setUp(messenger, this)
    }

    fun unregister(messenger: BinaryMessenger) {
        OpenHostApi.setUp(messenger, null)
    }

    override suspend fun openExternally(path: String, mimeType: String?): NativeOpenResultMessage =
        withContext(Dispatchers.Main) {
            try {
                val file = File(path)
                if (!file.exists()) {
                    return@withContext NativeOpenResultMessage(success = false, message = "File not found")
                }
                val authority = "${context.packageName}.attachment_engine.fileprovider"
                val uri = FileProvider.getUriForFile(context, authority, file)
                val mime = mimeType ?: inferMimeType(file.extension)
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.grantUriPermission(context.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                context.startActivity(intent)
                NativeOpenResultMessage(success = true, message = null)
            } catch (e: Exception) {
                NativeOpenResultMessage(success = false, message = e.message)
            }
        }

    private fun inferMimeType(extension: String): String {
        val ext = extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
    }
}
