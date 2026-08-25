// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Cocoa
import FlutterMacOS

/// Hands the file off to whichever installed app claims its type, via
/// `NSWorkspace.open(_:)` — the macOS equivalent of iOS's
/// `UIDocumentInteractionController`. Implements the Pigeon-generated
/// `OpenHostApi`.
class OpenChannel: NSObject, OpenHostApi {
  func register(with messenger: FlutterBinaryMessenger) {
    OpenHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    OpenHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
  }

  @MainActor
  func openExternally(path: String, mimeType: String?) async throws -> NativeOpenResultMessage {
    guard FileManager.default.fileExists(atPath: path) else {
      return NativeOpenResultMessage(success: false, message: "File not found")
    }
    let url = URL(fileURLWithPath: path)
    let opened = NSWorkspace.shared.open(url)
    return NativeOpenResultMessage(
      success: opened,
      message: opened ? nil : "No application registered for this file type")
  }
}
