import Flutter
import QuickLook
import UIKit

/// In-app Office document viewer for iOS, backed by Apple's QuickLook
/// framework (`QLPreviewController`). Zero third-party dependency: QuickLook
/// ships with every iOS install and natively renders doc/docx/xls/xlsx/
/// ppt/pptx/rtf and more.
///
/// Presented modally from the root Flutter view controller, mirroring the
/// modal-presentation pattern already used by `ShareChannel`/`OpenChannel`
/// (`UIActivityViewController`/`UIDocumentInteractionController`) rather than
/// introducing a new platform-view-embedding idiom for this one feature.
///
/// QuickLook requires a local file URL — it cannot preview remote URLs or
/// in-memory data directly, so callers must resolve the attachment to a
/// local path (as `AttachmentResolver` already guarantees) before invoking
/// this channel.
///
/// Implements the Pigeon-generated `OfficeHostApi`.
class OfficePreviewChannel: NSObject, OfficeHostApi, QLPreviewControllerDataSource {
  private var previewItemURL: URL?

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
    self.previewItemURL = URL(fileURLWithPath: path)

    guard let presenter = ShareChannel.topViewController() else {
      throw PigeonError(code: "no_presenter", message: "No presenting view controller", details: nil)
    }
    let preview = QLPreviewController()
    preview.dataSource = self
    presenter.present(preview, animated: true, completion: nil)
  }

  // MARK: QLPreviewControllerDataSource

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewItemURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    previewItemURL! as QLPreviewItem
  }
}
