// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Cocoa
import FlutterMacOS

/// AttachmentEnginePlugin (macOS): registers one focused channel/platform-view
/// per capability, mirroring `AttachmentEnginePlugin.swift` on iOS —
/// identical channel/method names so the Dart side is platform-agnostic.
///
/// Implemented: PDF (PDFKit), audio (AVFoundation), video (AVKit, embedded
/// via `FlutterPlatformViewFactory`), share (`NSSharingServicePicker`),
/// open-externally (`NSWorkspace.open`), office preview (`QLPreviewPanel`),
/// paths (`NSSearchPathForDirectoriesInDomains`), download (`URLSession`).
/// Webview embedding is handled by the official `webview_flutter` package
/// instead, at the app-facing layer — not through this plugin.
public class AttachmentEnginePlugin: NSObject, FlutterPlugin {
  private var legacyChannel: FlutterMethodChannel!

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
    let messenger = registrar.messenger

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
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
