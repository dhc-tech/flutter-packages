// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

package com.dhc.attachment_engine

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Replaces `video_player`. Embeds a [TextureView] backed by [android.media.MediaPlayer]
 * (Media3/ExoPlayer would be preferable for adaptive streaming, but was intentionally avoided here
 * to keep this pass free of additional third-party Gradle dependencies — see README "Known
 * limitations": no adaptive bitrate/DASH/HLS support).
 */
class VideoPlayerEntry(val playerId: String, private val messenger: BinaryMessenger) {
  val mediaPlayer = MediaPlayer()
  var surface: Surface? = null
  var texture: SurfaceTexture? = null
  private val handler = Handler(Looper.getMainLooper())
  private var progressRunnable: Runnable? = null
  var eventSink: EventChannel.EventSink? = null
  private val eventChannel =
      EventChannel(messenger, "attachment_engine/video_events/$playerId").also {
        it.setStreamHandler(
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

  fun attachSurface(newSurface: Surface) {
    surface = newSurface
    mediaPlayer.setSurface(newSurface)
  }

  fun load(path: String?, url: String?) {
    try {
      mediaPlayer.reset()
      mediaPlayer.setDataSource(path ?: url ?: "")
      surface?.let { mediaPlayer.setSurface(it) }
      mediaPlayer.setOnPreparedListener {
        emit("ready")
        startProgressLoop()
      }
      mediaPlayer.setOnCompletionListener { emit("completed") }
      mediaPlayer.setOnErrorListener { _, _, _ ->
        emit("error")
        true
      }
      emit("buffering")
      mediaPlayer.prepareAsync()
    } catch (_: Exception) {
      emit("error")
    }
  }

  fun play() {
    mediaPlayer.start()
    emit("playing")
  }

  fun pause() {
    mediaPlayer.pause()
    emit("paused")
  }

  fun seek(ms: Int) = mediaPlayer.seekTo(ms)

  fun setSpeed(speed: Float) {
    try {
      mediaPlayer.playbackParams = mediaPlayer.playbackParams.setSpeed(speed)
    } catch (_: Exception) {}
  }

  fun setVolume(volume: Float) = mediaPlayer.setVolume(volume, volume)

  private fun startProgressLoop() {
    progressRunnable?.let { handler.removeCallbacks(it) }
    val runnable =
        object : Runnable {
          override fun run() {
            try {
              eventSink?.success(
                  mapOf(
                      "state" to if (mediaPlayer.isPlaying) "playing" else "paused",
                      "positionMs" to mediaPlayer.currentPosition,
                      "durationMs" to mediaPlayer.duration,
                      "width" to mediaPlayer.videoWidth,
                      "height" to mediaPlayer.videoHeight,
                  ),
              )
            } catch (_: Exception) {}
            handler.postDelayed(this, 250)
          }
        }
    progressRunnable = runnable
    handler.post(runnable)
  }

  private fun emit(state: String) {
    eventSink?.success(mapOf("state" to state))
  }

  fun dispose() {
    progressRunnable?.let { handler.removeCallbacks(it) }
    eventChannel.setStreamHandler(null)
    try {
      mediaPlayer.release()
    } catch (_: Exception) {}
    texture?.release()
  }
}

/**
 * Shared registry so the control [MethodChannel] and the [PlatformView] factory (created lazily by
 * the Flutter engine when the widget attaches) both operate on the same native player instance for
 * a given `playerId`.
 */
/**
 * Method calls (load/play/pause/seek/setSpeed/setVolume/dispose) are dispatched through the
 * Pigeon-generated [VideoHostApi]. The platform-view factory below stays hand-registered (it isn't
 * a method call), and playback-state *events* stay on a hand-written per-`playerId` `EventChannel`
 * for the same reason as [AudioChannel] — see the note in
 * `attachment_engine_platform_interface/pigeons/messages.dart`.
 */
class VideoChannel(private val messenger: BinaryMessenger) : VideoHostApi {
  companion object {
    const val VIEW_TYPE = "attachment_engine/video_view"
  }

  val entries = mutableMapOf<String, VideoPlayerEntry>()

  fun register() {
    VideoHostApi.setUp(messenger, this)
  }

  fun unregister() {
    VideoHostApi.setUp(messenger, null)
    entries.keys.toList().forEach { disposeEntry(it) }
  }

  fun entryFor(playerId: String): VideoPlayerEntry {
    return entries.getOrPut(playerId) { VideoPlayerEntry(playerId, messenger) }
  }

  private fun disposeEntry(playerId: String) {
    entries.remove(playerId)?.dispose()
  }

  override suspend fun load(playerId: String, filePath: String?, url: String?) {
    entryFor(playerId).load(filePath, url)
  }

  override suspend fun play(playerId: String) {
    entries[playerId]?.play()
  }

  override suspend fun pause(playerId: String) {
    entries[playerId]?.pause()
  }

  override suspend fun seek(playerId: String, positionMs: Long) {
    entries[playerId]?.seek(positionMs.toInt())
  }

  override suspend fun setSpeed(playerId: String, speed: Double) {
    entries[playerId]?.setSpeed(speed.toFloat())
  }

  override suspend fun setVolume(playerId: String, volume: Double) {
    entries[playerId]?.setVolume(volume.toFloat())
  }

  override suspend fun dispose(playerId: String) {
    disposeEntry(playerId)
  }
}

class VideoPlatformViewFactory(private val videoChannel: VideoChannel) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    @Suppress("UNCHECKED_CAST") val params = args as? Map<String, Any?>
    val playerId = params?.get("playerId") as? String ?: viewId.toString()
    return VideoPlatformViewImpl(context, videoChannel.entryFor(playerId))
  }
}

private class VideoPlatformViewImpl(context: Context, private val entry: VideoPlayerEntry) :
    PlatformView, TextureView.SurfaceTextureListener {
  private val textureView = TextureView(context)

  init {
    textureView.surfaceTextureListener = this
  }

  override fun getView(): View = textureView

  override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
    entry.texture = surface
    entry.attachSurface(Surface(surface))
  }

  override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

  override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true

  override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

  override fun dispose() {
    // The native player entry outlives the view (pooled by Dart-side
    // VideoControllerPool); only the view's own resources are torn
    // down here.
  }
}
