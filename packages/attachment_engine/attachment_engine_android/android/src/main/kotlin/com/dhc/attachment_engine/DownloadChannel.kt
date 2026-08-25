package com.dhc.attachment_engine

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Replaces `dio`. Downloads over plain [HttpURLConnection] (avoiding
 * third-party OkHttp), reporting progress/completion/error over a shared
 * EventChannel, each event tagged with its `downloadId`.
 *
 * `startDownload`/`resumeDownload`/`cancelDownload` are dispatched through
 * the Pigeon-generated [DownloadHostApi]. Progress/completion/error
 * *events* stay on a hand-written shared `EventChannel` — Pigeon's
 * event-channel support models one stream per API, not the free-form,
 * multiplexed-by-payload stream this plugin already had; see the note in
 * `attachment_engine_platform_interface/pigeons/messages.dart`.
 */
class DownloadChannel : DownloadHostApi {
    companion object {
        const val EVENT_CHANNEL_NAME = "attachment_engine/download_events"
    }

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cancelled = mutableSetOf<String>()
    private var eventSink: EventChannel.EventSink? = null

    lateinit var eventChannel: EventChannel

    fun register(messenger: BinaryMessenger) {
        DownloadHostApi.setUp(messenger, this)
        eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    fun unregister(messenger: BinaryMessenger) {
        DownloadHostApi.setUp(messenger, null)
        eventChannel.setStreamHandler(null)
        executor.shutdownNow()
    }

    override suspend fun startDownload(url: String, headers: Map<String, String>, destPath: String): String =
        beginDownload(url, headers, destPath, resume = false)

    override suspend fun resumeDownload(url: String, headers: Map<String, String>, destPath: String): String =
        beginDownload(url, headers, destPath, resume = true)

    override suspend fun cancelDownload(downloadId: String) {
        cancelled.add(downloadId)
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    /** Sidecar file next to [destPath] tracking the source URL for a partial download. */
    private fun partMetaFile(destPath: String): File = File("$destPath.part.meta")

    private fun writePartMeta(destPath: String, url: String) {
        try {
            partMetaFile(destPath).writeText(url)
        } catch (_: Exception) {
            // Best-effort: absence just disables resume validation, doesn't break download.
        }
    }

    private fun readPartMetaUrl(destPath: String): String? =
        try {
            partMetaFile(destPath).takeIf { it.exists() }?.readText()
        } catch (_: Exception) {
            null
        }

    private fun clearPartMeta(destPath: String) {
        try {
            partMetaFile(destPath).delete()
        } catch (_: Exception) {
        }
    }

    private fun beginDownload(
        url: String,
        headers: Map<String, String>,
        destPath: String,
        resume: Boolean,
    ): String {
        val downloadId = UUID.randomUUID().toString()

        executor.submit {
            var connection: HttpURLConnection? = null
            val destFile = File(destPath)
            // Only trust an existing partial file as resumable if its sidecar metadata
            // records the same source URL - otherwise a stale/foreign partial file could
            // be corrupted by appending unrelated data to it.
            val existingBytes =
                if (resume && destFile.exists() && readPartMetaUrl(destPath) == url) {
                    destFile.length()
                } else {
                    0L
                }
            if (existingBytes == 0L && destFile.exists()) {
                // Not a valid resumable partial - start clean to avoid corruption.
                destFile.delete()
            }
            try {
                connection = URL(url).openConnection() as HttpURLConnection
                headers.forEach { (k, v) -> connection.setRequestProperty(k, v) }
                if (existingBytes > 0) {
                    connection.setRequestProperty("Range", "bytes=$existingBytes-")
                }
                connection.connectTimeout = 30_000
                connection.readTimeout = 30_000
                connection.connect()

                val responseCode = connection.responseCode
                if (responseCode !in 200..299) {
                    emit(
                        mapOf(
                            "downloadId" to downloadId,
                            "type" to "error",
                            "message" to "HTTP $responseCode",
                        ),
                    )
                    return@submit
                }

                // Server may ignore the Range header (200 instead of 206): must restart
                // from scratch to avoid corrupting the destination file.
                val serverHonoredRange = responseCode == 206
                val append = existingBytes > 0 && serverHonoredRange
                var received = if (append) existingBytes else 0L
                val contentLength = connection.contentLengthLong
                val total = if (append && contentLength > 0) contentLength + existingBytes else contentLength

                destFile.parentFile?.mkdirs()
                if (!append && destFile.exists()) destFile.delete()
                writePartMeta(destPath, url)

                connection.inputStream.use { input ->
                    java.io.FileOutputStream(destFile, append).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            if (cancelled.contains(downloadId)) {
                                emit(
                                    mapOf(
                                        "downloadId" to downloadId,
                                        "type" to "error",
                                        "message" to "cancelled",
                                    ),
                                )
                                cancelled.remove(downloadId)
                                return@submit
                            }
                            val read = input.read(buffer)
                            if (read == -1) break
                            output.write(buffer, 0, read)
                            received += read
                            emit(
                                mapOf(
                                    "downloadId" to downloadId,
                                    "type" to "progress",
                                    "received" to received,
                                    "total" to total,
                                ),
                            )
                        }
                    }
                }
                clearPartMeta(destPath)
                emit(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "completed",
                        "path" to destPath,
                    ),
                )
            } catch (e: java.io.IOException) {
                val diskFull =
                    e.message?.contains("ENOSPC", ignoreCase = true) == true ||
                        e.message?.contains("No space left", ignoreCase = true) == true
                emit(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "error",
                        "message" to if (diskFull) "insufficient_storage" else (e.message ?: "download failed"),
                    ),
                )
            } catch (e: Exception) {
                emit(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "error",
                        "message" to (e.message ?: "download failed"),
                    ),
                )
            } finally {
                connection?.disconnect()
            }
        }

        return downloadId
    }
}
