// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

package com.dhc.attachment_engine

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Replaces `share_plus`. Uses `Intent.ACTION_SEND` with a FileProvider content URI. Implements the
 * Pigeon-generated [ShareHostApi].
 */
class ShareChannel(private val context: Context) : ShareHostApi {
  fun register(messenger: BinaryMessenger) {
    ShareHostApi.setUp(messenger, this)
  }

  fun unregister(messenger: BinaryMessenger) {
    ShareHostApi.setUp(messenger, null)
  }

  override suspend fun shareFile(path: String, text: String?) {
    withContext(Dispatchers.Main) {
      try {
        val file = File(path)
        val authority = "${context.packageName}.attachment_engine.fileprovider"
        val uri = FileProvider.getUriForFile(context, authority, file)
        val intent =
            Intent(Intent.ACTION_SEND).apply {
              type = context.contentResolver.getType(uri) ?: "*/*"
              putExtra(Intent.EXTRA_STREAM, uri)
              if (text != null) putExtra(Intent.EXTRA_TEXT, text)
              addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
              addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        context.startActivity(
            Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      } catch (e: Exception) {
        throw FlutterError("share_failed", e.message, null)
      }
    }
  }

  override suspend fun shareText(text: String) {
    withContext(Dispatchers.Main) {
      try {
        val intent =
            Intent(Intent.ACTION_SEND).apply {
              type = "text/plain"
              putExtra(Intent.EXTRA_TEXT, text)
              addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        context.startActivity(
            Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      } catch (e: Exception) {
        throw FlutterError("share_failed", e.message, null)
      }
    }
  }
}
