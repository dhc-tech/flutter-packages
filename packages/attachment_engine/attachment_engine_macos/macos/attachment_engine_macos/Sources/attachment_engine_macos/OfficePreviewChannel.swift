// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Cocoa
import FlutterMacOS
import Quartz

/// In-app Office document viewer for macOS, backed by Apple's QuickLook
/// framework (`QLPreviewPanel`) — the macOS equivalent of iOS's
/// `QLPreviewController`. Zero third-party dependency: QuickLook ships with
/// every macOS install and natively renders doc/docx/xls/xlsx/ppt/pptx/rtf
/// and more.
///
/// `QLPreviewPanel` is a shared, singleton panel (unlike iOS's per-use view
/// controller), so this channel becomes the panel's data source/delegate
/// only while a preview is active, and yields it back on close.
///
/// Implements the Pigeon-generated `OfficeHostApi`.
class OfficePreviewChannel: NSObject, OfficeHostApi, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  private var previewItemURL: NSURL?

  func register(with messenger: FlutterBinaryMessenger) {
    OfficeHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    OfficeHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
  }

  @MainActor
  func openOfficePreview(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else {
      throw PigeonError(code: "not_found", message: "File not found", details: nil)
    }
    guard let panel = QLPreviewPanel.shared() else {
      throw PigeonError(code: "no_panel", message: "QLPreviewPanel unavailable", details: nil)
    }
    self.previewItemURL = NSURL(fileURLWithPath: path)
    panel.dataSource = self
    panel.delegate = self
    panel.reloadData()
    panel.makeKeyAndOrderFront(nil)
  }

  // MARK: QLPreviewPanelDataSource

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    previewItemURL == nil ? 0 : 1
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    previewItemURL
  }
}
