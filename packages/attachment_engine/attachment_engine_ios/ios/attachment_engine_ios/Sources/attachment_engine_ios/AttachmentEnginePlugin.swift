// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Flutter
import UIKit

/// AttachmentEnginePlugin: registers one focused channel/platform-view per
/// capability, replacing the third-party plugins previously used (pdfx,
/// video_player, just_audio, share_plus, open_filex, dio, path_provider)
/// with hand-written native implementations. Webview embedding is handled
/// by the official `webview_flutter` package instead, at the app-facing
/// layer — not through this plugin. Mirrors `AttachmentEnginePlugin.kt` on
/// Android: identical channel/method names so the Dart side is
/// platform-agnostic.
public class AttachmentEnginePlugin: NSObject, FlutterPlugin {
  private var legacyChannel: FlutterMethodChannel!
  private var messenger: FlutterBinaryMessenger!

  private let pathsChannel = PathsChannel()
  private let pdfChannel = PdfChannel()
  private let downloadChannel = DownloadChannel()
  private let shareChannel = ShareChannel()
  private let openChannel = OpenChannel()
  private let officePreviewChannel = OfficePreviewChannel()
  private let audioChannel = AudioChannel()
  private let videoChannel = VideoChannel()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AttachmentEnginePlugin()
    let messenger = registrar.messenger()
    instance.messenger = messenger

    instance.legacyChannel = FlutterMethodChannel(
      name: "attachment_engine", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: instance.legacyChannel)

    instance.pathsChannel.register(with: messenger)
    instance.pdfChannel.register(with: messenger)
    instance.downloadChannel.register(with: messenger)
    instance.shareChannel.register(with: messenger)
    instance.openChannel.register(with: messenger)
    instance.officePreviewChannel.register(with: messenger)
    instance.audioChannel.register(with: messenger)
    instance.videoChannel.register(with: messenger)

    registrar.register(
      VideoPlatformViewFactory(videoChannel: instance.videoChannel),
      withId: VideoChannel.viewType)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    pathsChannel.unregister(with: messenger)
    pdfChannel.unregister(with: messenger)
    downloadChannel.unregister(with: messenger)
    shareChannel.unregister(with: messenger)
    openChannel.unregister(with: messenger)
    officePreviewChannel.unregister(with: messenger)
    audioChannel.unregister(with: messenger)
    videoChannel.unregister(with: messenger)
  }
}
