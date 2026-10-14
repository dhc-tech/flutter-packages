// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

package com.dhc.attachment_engine

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val TAG = "AttachmentEngineVideo"

/**
 * Replaces `video_player`. Embeds a [TextureView] backed by [android.media.MediaPlayer]
 * (Media3/ExoPlayer would be preferable for adaptive streaming, but was intentionally avoided here
 * to keep this pass free of additional third-party Gradle dependencies — see README "Known
 * limitations": no adaptive bitrate/DASH/HLS support).
 *
 * ## Surface lifecycle
 *
 * Playback is gated by four independent, explicit state flags rather than by call ordering or
 * timing — [surfaceAvailable], [prepared], [playRequested], [released]. [maybeStart] is the *only*
 * place `MediaPlayer.start()` is called, and only once all three positive flags hold and [released]
 * does not. This is deliberate: on some vendor decoders (observed on Samsung Exynos
 * `c2.exynos.h264.decoder`), calling `MediaPlayer.setSurface()` *after* `prepareAsync()` has
 * already started decoding is silently ignored — metadata (duration/width/height) keeps reporting
 * correctly (it's read from the container, not from the decoder pipeline), but no frame ever
 * reaches the new Surface. The fix is to never let decode start without a Surface already attached,
 * and to never resume/replace a Surface without knowing decode is actually paused first.
 */
class VideoPlayerEntry(val playerId: String, private val messenger: BinaryMessenger) {
  val mediaPlayer = MediaPlayer()

  // --- Explicit state (see class doc) ---------------------------------
  private var surface: Surface? = null
  private var surfaceAvailable = false
  private var prepared = false
  private var playRequested = false
  private var released = false

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

  init {
    Log.d(TAG, "ATTACHMENT_VIDEO_CREATED playerId=$playerId")
    // Fires exactly when the decoder pipeline has actually delivered a
    // frame to the attached Surface — the one Android-documented,
    // deterministic signal for "a frame rendered" that isn't just
    // "start() was called". Available since API 17; this app's minSdk is
    // well above that.
    mediaPlayer.setOnInfoListener { _, what, _ ->
      if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) {
        Log.d(TAG, "ATTACHMENT_FIRST_FRAME playerId=$playerId")
      }
      false
    }
  }

  // Requested-but-not-yet-loadable source, held while surfaceAvailable is
  // false. Replayed by attachSurface() the moment a surface exists.
  private var pendingSource: Pair<String?, String?>? = null

  /**
   * Called from [VideoPlatformViewImpl.onSurfaceTextureAvailable]. May fire more than once across
   * this entry's lifetime — a pooled entry can be reused by a new [VideoPlatformViewImpl] (widget
   * rebuild, navigating away and back) after its previous one was destroyed.
   */
  fun attachSurface(newSurface: Surface) {
    val identity = System.identityHashCode(newSurface)
    Log.d(TAG, "ATTACHMENT_SURFACE_CREATED playerId=$playerId surfaceId=$identity")
    if (released) return

    val hadSurfaceBefore = surfaceAvailable
    surface = newSurface
    surfaceAvailable = true

    val pending = pendingSource
    if (pending != null) {
      pendingSource = null
      doLoad(pending.first, pending.second)
      return
    }

    if (hadSurfaceBefore && prepared) {
      // A genuine mid-playback surface replacement (e.g. the platform view
      // was rebuilt while this pooled controller kept playing) — MediaPlayer
      // supports setSurface() here because playback has already reached a
      // steady, prepared state; this is not the same unsafe case as calling
      // it against a player still mid-prepareAsync().
      Log.d(TAG, "ATTACHMENT_SURFACE_REPLACED playerId=$playerId surfaceId=$identity")
      mediaPlayer.setSurface(newSurface)
    } else if (!prepared) {
      // Surface arrived but nothing has been loaded onto this entry yet
      // (e.g. acquired from the pool ahead of any load() call) — nothing to
      // do until load() is actually called.
      return
    } else {
      mediaPlayer.setSurface(newSurface)
    }
    maybeStart()
  }

  /**
   * Called from [VideoPlatformViewImpl.onSurfaceTextureDestroyed]. Only clears this entry's surface
   * state if [oldSurface] is the surface it is *currently* tracking — guards the exact rebuild race
   * the Surface-A/ Surface-B ordering concern describes: if a new surface has already attached by
   * the time the old one's destroy callback arrives, this must not clear the new, live surface out
   * from under the player.
   */
  fun detachSurface(oldSurface: Surface) {
    val identity = System.identityHashCode(oldSurface)
    if (surface !== oldSurface) {
      Log.d(
          TAG,
          "ATTACHMENT_SURFACE_DESTROYED playerId=$playerId surfaceId=$identity " +
              "(stale — a newer surface is already attached, ignoring)",
      )
      return
    }
    Log.d(TAG, "ATTACHMENT_SURFACE_DESTROYED playerId=$playerId surfaceId=$identity")
    surfaceAvailable = false
    surface = null
    if (released) return
    try {
      // Pause rather than leave the player running with no surface — video
      // decode with nowhere to render is wasted work, and resuming later is
      // just attachSurface() + maybeStart() once a surface exists again.
      if (mediaPlayer.isPlaying) mediaPlayer.pause()
      mediaPlayer.setSurface(null)
    } catch (_: Exception) {}
  }

  fun load(path: String?, url: String?) {
    Log.d(TAG, "PLAYER_INITIALIZING playerId=$playerId path=$path url=$url")
    prepared = false
    if (!surfaceAvailable) {
      pendingSource = path to url
      emit("buffering")
      return
    }
    doLoad(path, url)
  }

  private fun doLoad(path: String?, url: String?) {
    if (released) return
    try {
      Log.d(TAG, "ATTACHMENT_PLAYER_CREATED playerId=$playerId")
      mediaPlayer.reset()
      prepared = false
      mediaPlayer.setDataSource(path ?: url ?: "")
      // Surface is attached BEFORE prepareAsync() — never the other way
      // around. This ordering is the actual fix: some vendor decoders
      // ignore a Surface assigned after decode has already started.
      surface?.let { mediaPlayer.setSurface(it) }
      mediaPlayer.setOnPreparedListener {
        if (released) return@setOnPreparedListener
        prepared = true
        Log.d(
            TAG,
            "ATTACHMENT_PLAYER_PREPARED playerId=$playerId " +
                "width=${mediaPlayer.videoWidth} height=${mediaPlayer.videoHeight} " +
                "durationMs=${mediaPlayer.duration}",
        )
        emit("ready")
        maybeStart()
        startProgressLoop()
      }
      mediaPlayer.setOnCompletionListener {
        if (released) return@setOnCompletionListener
        emit("completed")
      }
      mediaPlayer.setOnErrorListener { _, what, extra ->
        if (released) return@setOnErrorListener true
        Log.e(TAG, "PLAYER_ERROR playerId=$playerId what=$what extra=$extra path=$path url=$url")
        prepared = false
        emit("error")
        true
      }
      emit("buffering")
      Log.d(TAG, "ATTACHMENT_PLAYER_PREPARING playerId=$playerId")
      mediaPlayer.prepareAsync()
    } catch (e: Exception) {
      Log.e(TAG, "PLAYER_INIT_FAILED playerId=$playerId error=${e.message}")
      emit("error")
    }
  }

  /**
   * The single gate for `MediaPlayer.start()`. Only called when every positive condition holds and
   * the entry hasn't been released — see the class doc for why this replaces relying on call-site
   * ordering.
   */
  private fun maybeStart() {
    if (released) return
    if (surfaceAvailable && prepared && playRequested) {
      Log.d(TAG, "ATTACHMENT_PLAYER_STARTED playerId=$playerId")
      mediaPlayer.start()
      emit("playing")
    }
  }

  fun play() {
    playRequested = true
    maybeStart()
  }

  fun pause() {
    playRequested = false
    if (released) return
    try {
      if (mediaPlayer.isPlaying) mediaPlayer.pause()
    } catch (_: Exception) {}
    emit("paused")
  }

  fun seek(ms: Int) {
    if (released) return
    try {
      mediaPlayer.seekTo(ms)
    } catch (_: Exception) {}
  }

  fun setSpeed(speed: Float) {
    if (released) return
    try {
      mediaPlayer.playbackParams = mediaPlayer.playbackParams.setSpeed(speed)
    } catch (_: Exception) {}
  }

  fun setVolume(volume: Float) {
    if (released) return
    try {
      mediaPlayer.setVolume(volume, volume)
    } catch (_: Exception) {}
  }

  private fun startProgressLoop() {
    progressRunnable?.let { handler.removeCallbacks(it) }
    val runnable =
        object : Runnable {
          override fun run() {
            if (released) return
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
            if (!released) handler.postDelayed(this, 250)
          }
        }
    progressRunnable = runnable
    handler.post(runnable)
  }

  private fun emit(state: String) {
    eventSink?.success(mapOf("state" to state))
  }

  fun dispose() {
    // Set FIRST, before touching the player at all — every async callback
    // above (onPrepared/onCompletion/onError/the progress Runnable) checks
    // this and no-ops if set, so a callback racing this dispose() can never
    // call start()/setSurface() against a player already being torn down.
    released = true
    Log.d(TAG, "ATTACHMENT_PLAYER_RELEASED playerId=$playerId")
    progressRunnable?.let { handler.removeCallbacks(it) }
    eventChannel.setStreamHandler(null)
    try {
      mediaPlayer.release()
    } catch (_: Exception) {}
    texture?.release()
  }
}

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

  // The exact Surface object handed to entry.attachSurface() — retained so
  // onSurfaceTextureDestroyed() can hand back that *same* object for the
  // entry's identity check. Constructing a fresh `Surface(surfaceTexture)`
  // at destroy time would produce a different object instance wrapping the
  // same texture, which would never match by reference and would defeat
  // the whole stale-surface guard.
  private var attachedSurface: Surface? = null

  init {
    textureView.surfaceTextureListener = this
  }

  override fun getView(): View = textureView

  override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
    entry.texture = surface
    val newSurface = Surface(surface)
    attachedSurface = newSurface
    entry.attachSurface(newSurface)
  }

  override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

  override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
    // The player entry must never keep decoding into a Surface Android has
    // already torn down.
    attachedSurface?.let { entry.detachSurface(it) }
    attachedSurface = null
    return true
  }

  override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

  override fun dispose() {
    // The native player entry outlives the view (pooled by Dart-side
    // VideoControllerPool); only the view's own resources are torn
    // down here.
  }
}
