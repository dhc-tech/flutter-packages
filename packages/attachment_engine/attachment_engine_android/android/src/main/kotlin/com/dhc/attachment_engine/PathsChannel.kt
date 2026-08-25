package com.dhc.attachment_engine

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger

/**
 * Replaces `path_provider`: exposes app-private storage directories.
 * Implements the Pigeon-generated [PathsHostApi].
 */
class PathsChannel(private val context: Context) : PathsHostApi {
    fun register(messenger: BinaryMessenger) {
        PathsHostApi.setUp(messenger, this)
    }

    fun unregister(messenger: BinaryMessenger) {
        PathsHostApi.setUp(messenger, null)
    }

    override suspend fun getApplicationSupportDirectory(): String = context.filesDir.absolutePath

    override suspend fun getApplicationCacheDirectory(): String = context.cacheDir.absolutePath
}
