// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import AVFoundation
import Flutter
import Foundation

/// Replaces `just_audio`. Uses `AVAudioPlayer` for local files and
/// `AVPlayer` for streaming remote URLs, mirroring
/// `attachment_engine/audio` (method channel) +
/// `attachment_engine/audio_events/{playerId}` (per-instance event
/// channel) used on Android/Dart.
class AudioPlayerEntry: NSObject, AVAudioPlayerDelegate {
  let playerId: String
  var audioPlayer: AVAudioPlayer?
  var avPlayer: AVPlayer?
  var eventSink: FlutterEventSink?
  private var eventChannel: FlutterEventChannel?
  private var progressTimer: Timer?
  private var playerItemObservation: NSKeyValueObservation?

  init(playerId: String, messenger: FlutterBinaryMessenger) {
    self.playerId = playerId
    super.init()
    eventChannel = FlutterEventChannel(
      name: "attachment_engine/audio_events/\(playerId)", binaryMessenger: messenger)
    eventChannel?.setStreamHandler(
      AudioStreamHandler(onListen: { [weak self] sink in
        self?.eventSink = sink
      }, onCancel: { [weak self] in
        self?.eventSink = nil
      }))
  }

  func load(path: String?, url: String?) {
    stopTimer()
    emit(state: "buffering")
    if let path = path {
      do {
        let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player
        avPlayer = nil
        emit(state: "ready")
        startTimer()
      } catch {
        emit(state: "error")
      }
    } else if let url = url, let remoteUrl = URL(string: url) {
      audioPlayer = nil
      let item = AVPlayerItem(url: remoteUrl)
      let player = AVPlayer(playerItem: item)
      avPlayer = player
      NotificationCenter.default.addObserver(
        self, selector: #selector(didFinishPlaying),
        name: .AVPlayerItemDidPlayToEndTime, object: item)
      playerItemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard let self = self else { return }
        if item.status == .readyToPlay {
          self.emit(state: "ready")
          self.startTimer()
        } else if item.status == .failed {
          self.emit(state: "error")
        }
      }
    } else {
      emit(state: "error")
    }
  }

  @objc private func didFinishPlaying() {
    emit(state: "completed")
  }

  func play() {
    audioPlayer?.play()
    avPlayer?.play()
    emit(state: "playing")
  }

  func pause() {
    audioPlayer?.pause()
    avPlayer?.pause()
    emit(state: "paused")
  }

  func seek(ms: Int) {
    let time = Double(ms) / 1000.0
    if let audioPlayer = audioPlayer {
      audioPlayer.currentTime = time
    } else if let avPlayer = avPlayer {
      avPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
    }
  }

  func setSpeed(_ speed: Float) {
    if let audioPlayer = audioPlayer {
      audioPlayer.enableRate = true
      audioPlayer.rate = speed
    } else if let avPlayer = avPlayer {
      avPlayer.rate = speed
    }
  }

  func setVolume(_ volume: Float) {
    audioPlayer?.volume = volume
    avPlayer?.volume = volume
  }

  private func startTimer() {
    stopTimer()
    let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.emitProgress()
    }
    RunLoop.main.add(timer, forMode: .common)
    progressTimer = timer
  }

  private func stopTimer() {
    progressTimer?.invalidate()
    progressTimer = nil
  }

  private func emitProgress() {
    if let audioPlayer = audioPlayer {
      emit(
        state: audioPlayer.isPlaying ? "playing" : "paused",
        positionMs: Int(audioPlayer.currentTime * 1000),
        durationMs: Int(audioPlayer.duration * 1000))
    } else if let avPlayer = avPlayer {
      let positionMs = Int(avPlayer.currentTime().seconds * 1000)
      let durationMs = avPlayer.currentItem?.duration.seconds.isFinite == true
        ? Int((avPlayer.currentItem?.duration.seconds ?? 0) * 1000) : nil
      emit(
        state: avPlayer.rate > 0 ? "playing" : "paused", positionMs: positionMs,
        durationMs: durationMs)
    }
  }

  private func emit(state: String, positionMs: Int? = nil, durationMs: Int? = nil) {
    var event: [String: Any] = ["state": state]
    if let positionMs = positionMs { event["positionMs"] = positionMs }
    if let durationMs = durationMs { event["durationMs"] = durationMs }
    eventSink?(event)
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    emit(state: flag ? "completed" : "error")
  }

  func dispose() {
    stopTimer()
    audioPlayer?.stop()
    avPlayer?.pause()
    playerItemObservation?.invalidate()
    NotificationCenter.default.removeObserver(self)
    eventChannel?.setStreamHandler(nil)
  }
}

private class AudioStreamHandler: NSObject, FlutterStreamHandler {
  let onListen: (FlutterEventSink?) -> Void
  let onCancel: () -> Void

  init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
    self.onListen = onListen
    self.onCancel = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    onListen(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancel()
    return nil
  }
}

/// Method calls (load/play/pause/seek/setSpeed/setVolume/dispose) are
/// dispatched through the Pigeon-generated `AudioHostApi`. Playback-state
/// *events* stay on the hand-written per-`playerId` `FlutterEventChannel`
/// above (`AudioPlayerEntry`/`AudioStreamHandler`) — Pigeon's event-channel
/// support doesn't cleanly express a channel name keyed by an id chosen
/// dynamically at runtime; see the note in
/// `attachment_engine_platform_interface/pigeons/messages.dart`.
class AudioChannel: NSObject, AudioHostApi {
  private var messenger: FlutterBinaryMessenger!
  private var entries: [String: AudioPlayerEntry] = [:]

  func register(with messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    AudioHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    AudioHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    for entry in entries.values { entry.dispose() }
    entries.removeAll()
  }

  private func entry(for playerId: String) -> AudioPlayerEntry {
    if let existing = entries[playerId] { return existing }
    let entry = AudioPlayerEntry(playerId: playerId, messenger: messenger)
    entries[playerId] = entry
    return entry
  }

  @MainActor
  func load(playerId: String, filePath: String?, url: String?) async throws {
    entry(for: playerId).load(path: filePath, url: url)
  }

  @MainActor
  func play(playerId: String) async throws {
    entries[playerId]?.play()
  }

  @MainActor
  func pause(playerId: String) async throws {
    entries[playerId]?.pause()
  }

  @MainActor
  func seek(playerId: String, positionMs: Int64) async throws {
    entries[playerId]?.seek(ms: Int(positionMs))
  }

  @MainActor
  func setSpeed(playerId: String, speed: Double) async throws {
    entries[playerId]?.setSpeed(Float(speed))
  }

  @MainActor
  func setVolume(playerId: String, volume: Double) async throws {
    entries[playerId]?.setVolume(Float(volume))
  }

  @MainActor
  func dispose(playerId: String) async throws {
    entries.removeValue(forKey: playerId)?.dispose()
  }
}
