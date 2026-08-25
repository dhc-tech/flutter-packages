package com.dhc.attachment_engine

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Replaces `pdfx`. Uses [android.graphics.pdf.PdfRenderer] to open a PDF
 * and render pages to PNG bitmaps, keyed by an opaque handle string so the
 * Dart side can hold multiple documents open concurrently.
 *
 * Implements the Pigeon-generated [PdfHostApi] (see the codegen'd
 * `Messages.g.kt`, produced from
 * `attachment_engine_platform_interface/pigeons/messages.dart`) instead of
 * a hand-written `MethodChannel`.
 */
class PdfChannel : PdfHostApi {
    private data class OpenDoc(val fd: ParcelFileDescriptor, val renderer: PdfRenderer)

    private val openDocs = mutableMapOf<String, OpenDoc>()

    fun register(messenger: BinaryMessenger) {
        PdfHostApi.setUp(messenger, this)
    }

    fun unregister(messenger: BinaryMessenger) {
        PdfHostApi.setUp(messenger, null)
        openDocs.values.forEach {
            try {
                it.renderer.close()
                it.fd.close()
            } catch (_: Exception) {
            }
        }
        openDocs.clear()
    }

    override suspend fun open(path: String): PdfOpenResultMessage =
        withContext(Dispatchers.IO) {
            val file = File(path)
            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(fd)
            val handle = UUID.randomUUID().toString()
            openDocs[handle] = OpenDoc(fd, renderer)
            PdfOpenResultMessage(handle = handle, pageCount = renderer.pageCount.toLong())
        }

    override suspend fun renderPage(
        handle: String,
        index: Long,
        width: Long,
        height: Long,
    ): ByteArray =
        withContext(Dispatchers.IO) {
            val doc = openDocs[handle] ?: throw FlutterError("bad_handle", "Unknown PDF handle", null)
            val safeWidth = width.toInt().coerceAtLeast(1)
            val safeHeight = height.toInt().coerceAtLeast(1)
            val page = doc.renderer.openPage(index.toInt())
            try {
                val scale = minOf(safeWidth.toDouble() / page.width, safeHeight.toDouble() / page.height)
                val bmpWidth = (page.width * scale).toInt().coerceAtLeast(1)
                val bmpHeight = (page.height * scale).toInt().coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(bmpWidth, bmpHeight, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                stream.toByteArray()
            } finally {
                page.close()
            }
        }

    override suspend fun close(handle: String) {
        withContext(Dispatchers.IO) {
            val doc = openDocs.remove(handle)
            try {
                doc?.renderer?.close()
                doc?.fd?.close()
            } catch (_: Exception) {
            }
        }
    }
}
