import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS

/// Embeds an `AVPlayer`-backed `AVPlayerLayer` through a
/// `FlutterPlatformViewFactory` (macOS's platform-view embedding API is
/// simpler than iOS's — no `FlutterPlatformView` wrapper protocol; the
/// factory returns the `NSView` directly, and there is no `frame`
/// parameter to `createWithViewIdentifier`), mirroring the Android
/// `TextureView`/`MediaPlayer` implementation: control
/// (`load`/`play`/`pause`/`seek`/`setSpeed`/`setVolume`/`dispose`) goes
/// over `attachment_engine/video`, and playback/buffering events go over
/// `attachment_engine/video_events/{playerId}`.
class VideoPlayerEntry: NSObject {
  let playerId: String
  let player = AVPlayer()
  var eventSink: FlutterEventSink?
  private var eventChannel: FlutterEventChannel?
  private var progressTimer: Timer?
  private var itemObservation: NSKeyValueObservation?

  init(playerId: String, messenger: FlutterBinaryMessenger) {
    self.playerId = playerId
    super.init()
    eventChannel = FlutterEventChannel(
      name: "attachment_engine/video_events/\(playerId)", binaryMessenger: messenger)
    eventChannel?.setStreamHandler(
      VideoStreamHandler(onListen: { [weak self] sink in
        self?.eventSink = sink
      }, onCancel: { [weak self] in
        self?.eventSink = nil
      }))
  }

  func load(path: String?, url: String?) {
    stopTimer()
    emit(state: "buffering")
    let mediaUrl: URL?
    if let path = path {
      mediaUrl = URL(fileURLWithPath: path)
    } else if let url = url {
      mediaUrl = URL(string: url)
    } else {
      mediaUrl = nil
    }
    guard let mediaUrl = mediaUrl else {
      emit(state: "error")
      return
    }
    let item = AVPlayerItem(url: mediaUrl)
    NotificationCenter.default.addObserver(
      self, selector: #selector(didFinishPlaying), name: .AVPlayerItemDidPlayToEndTime,
      object: item)
    itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard let self = self else { return }
      switch item.status {
      case .readyToPlay:
        self.emit(state: "ready")
        self.startTimer()
      case .failed:
        self.emit(state: "error")
      default:
        break
      }
    }
    player.replaceCurrentItem(with: item)
  }

  @objc private func didFinishPlaying() {
    emit(state: "completed")
  }

  func play() {
    player.play()
    emit(state: "playing")
  }

  func pause() {
    player.pause()
    emit(state: "paused")
  }

  func seek(ms: Int) {
    player.seek(to: CMTime(seconds: Double(ms) / 1000.0, preferredTimescale: 1000))
  }

  func setSpeed(_ speed: Float) {
    player.rate = speed
  }

  func setVolume(_ volume: Float) {
    player.volume = volume
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
    guard let item = player.currentItem else { return }
    let positionMs = Int(player.currentTime().seconds * 1000)
    let durationSeconds = item.duration.seconds
    let durationMs = durationSeconds.isFinite ? Int(durationSeconds * 1000) : nil
    var event: [String: Any] = [
      "state": player.rate > 0 ? "playing" : "paused",
      "positionMs": positionMs,
    ]
    if let durationMs = durationMs { event["durationMs"] = durationMs }
    if let track = item.asset.tracks(withMediaType: .video).first {
      let size = track.naturalSize.applying(track.preferredTransform)
      event["width"] = abs(size.width)
      event["height"] = abs(size.height)
    }
    eventSink?(event)
  }

  private func emit(state: String) {
    eventSink?(["state": state])
  }

  func dispose() {
    stopTimer()
    player.pause()
    itemObservation?.invalidate()
    NotificationCenter.default.removeObserver(self)
    eventChannel?.setStreamHandler(nil)
  }
}

private class VideoStreamHandler: NSObject, FlutterStreamHandler {
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

/// Shared registry so the control API and the platform view factory both
/// operate on the same native player instance for a given `playerId`.
///
/// Method calls (load/play/pause/seek/setSpeed/setVolume/dispose) are
/// dispatched through the Pigeon-generated `VideoHostApi`. The platform
/// view factory below stays hand-registered (it isn't a method call), and
/// playback-state *events* stay on the hand-written per-`playerId`
/// `FlutterEventChannel` above (`VideoPlayerEntry`/`VideoStreamHandler`) —
/// see the note in `attachment_engine_platform_interface/pigeons/messages.dart`.
class VideoChannel: NSObject, VideoHostApi {
  static let viewType = "attachment_engine/video_view"

  private var messenger: FlutterBinaryMessenger!
  var entries: [String: VideoPlayerEntry] = [:]

  func register(with messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    VideoHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    VideoHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    for entry in entries.values { entry.dispose() }
    entries.removeAll()
  }

  func entry(for playerId: String) -> VideoPlayerEntry {
    if let existing = entries[playerId] { return existing }
    let entry = VideoPlayerEntry(playerId: playerId, messenger: messenger)
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

/// macOS's `FlutterPlatformViewFactory` has no `FlutterPlatformView`
/// wrapper protocol and no `frame` parameter — it returns the `NSView`
/// directly.
class VideoPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let videoChannel: VideoChannel

  init(videoChannel: VideoChannel) {
    self.videoChannel = videoChannel
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let params = args as? [String: Any]
    let playerId = (params?["playerId"] as? String) ?? String(viewId)
    return VideoPlayerNSView(entry: videoChannel.entry(for: playerId))
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private class VideoPlayerNSView: NSView {
  private let playerLayer: AVPlayerLayer

  init(entry: VideoPlayerEntry) {
    playerLayer = AVPlayerLayer(player: entry.player)
    playerLayer.videoGravity = .resizeAspect
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    layer?.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layout() {
    super.layout()
    playerLayer.frame = bounds
  }
}
