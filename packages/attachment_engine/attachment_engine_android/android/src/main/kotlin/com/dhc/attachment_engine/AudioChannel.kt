package com.dhc.attachment_engine

import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Replaces `just_audio`. Uses [android.media.MediaPlayer] for both local
 * and streaming remote audio playback (a pragmatic simplification vs.
 * Media3/ExoPlayer — see README "Known limitations": no adaptive
 * streaming, but sufficient for direct-URL MP3/AAC/etc. playback).
 *
 * Method calls (load/play/pause/seek/setSpeed/setVolume/dispose) are
 * dispatched through the Pigeon-generated [AudioHostApi]. Playback-state
 * *events* stay on a hand-written per-`playerId` `EventChannel`: Pigeon's
 * event-channel support doesn't cleanly express a channel name keyed by an
 * id chosen dynamically at runtime (see the note in
 * `attachment_engine_platform_interface/pigeons/messages.dart`).
 */
class AudioChannel(private val messenger: BinaryMessenger) : AudioHostApi {
    private class PlayerEntry(val player: MediaPlayer) {
        var eventSink: EventChannel.EventSink? = null
        var eventChannel: EventChannel? = null
        var progressRunnable: Runnable? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private val players = mutableMapOf<String, PlayerEntry>()

    fun register() {
        AudioHostApi.setUp(messenger, this)
    }

    fun unregister() {
        AudioHostApi.setUp(messenger, null)
        players.keys.toList().forEach { disposePlayer(it) }
    }

    override suspend fun load(playerId: String, filePath: String?, url: String?) {
        val entry = ensureEntry(playerId)
        try {
            entry.player.reset()
            entry.player.setDataSource(filePath ?: url ?: "")
            entry.player.setOnPreparedListener {
                emitState(playerId, "ready")
                startProgressLoop(playerId)
            }
            entry.player.setOnCompletionListener { emitState(playerId, "completed") }
            entry.player.setOnErrorListener { _, _, _ ->
                emitState(playerId, "error")
                true
            }
            emitState(playerId, "buffering")
            entry.player.prepareAsync()
        } catch (e: Exception) {
            throw FlutterError("load_failed", e.message, null)
        }
    }

    override suspend fun play(playerId: String) {
        players[playerId]?.player?.start()
        emitState(playerId, "playing")
    }

    override suspend fun pause(playerId: String) {
        players[playerId]?.player?.pause()
        emitState(playerId, "paused")
    }

    override suspend fun seek(playerId: String, positionMs: Long) {
        players[playerId]?.player?.seekTo(positionMs.toInt())
    }

    override suspend fun setSpeed(playerId: String, speed: Double) {
        try {
            players[playerId]?.player?.let {
                it.playbackParams = it.playbackParams.setSpeed(speed.toFloat())
            }
        } catch (_: Exception) {
        }
    }

    override suspend fun setVolume(playerId: String, volume: Double) {
        players[playerId]?.player?.setVolume(volume.toFloat(), volume.toFloat())
    }

    override suspend fun dispose(playerId: String) {
        disposePlayer(playerId)
    }

    private fun ensureEntry(playerId: String): PlayerEntry {
        return players.getOrPut(playerId) {
            val entry = PlayerEntry(MediaPlayer())
            val eventChannel = EventChannel(messenger, "attachment_engine/audio_events/$playerId")
            eventChannel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        entry.eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        entry.eventSink = null
                    }
                },
            )
            entry.eventChannel = eventChannel
            entry
        }
    }

    private fun startProgressLoop(playerId: String) {
        val entry = players[playerId] ?: return
        entry.progressRunnable?.let { handler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                val e = players[playerId] ?: return
                try {
                    e.eventSink?.success(
                        mapOf(
                            "state" to if (e.player.isPlaying) "playing" else "paused",
                            "positionMs" to e.player.currentPosition,
                            "durationMs" to e.player.duration,
                        ),
                    )
                } catch (_: Exception) {
                }
                handler.postDelayed(this, 250)
            }
        }
        entry.progressRunnable = runnable
        handler.post(runnable)
    }

    private fun emitState(playerId: String, state: String) {
        players[playerId]?.eventSink?.success(mapOf("state" to state))
    }

    private fun disposePlayer(playerId: String) {
        val entry = players.remove(playerId) ?: return
        entry.progressRunnable?.let { handler.removeCallbacks(it) }
        entry.eventChannel?.setStreamHandler(null)
        try {
            entry.player.release()
        } catch (_: Exception) {
        }
    }
}
