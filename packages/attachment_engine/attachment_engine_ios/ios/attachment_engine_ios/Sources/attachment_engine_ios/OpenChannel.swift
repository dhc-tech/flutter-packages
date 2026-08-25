import Flutter
import UIKit
import UniformTypeIdentifiers

/// Replaces `open_filex`. Uses `UIDocumentInteractionController` to hand
/// the file off to whichever installed app claims its type (falls back to
/// reporting failure if no app can open it, mirroring Android's
/// `ACTION_VIEW` "no activity found" case).
///
/// Implements the Pigeon-generated `OpenHostApi`.
class OpenChannel: NSObject, OpenHostApi, UIDocumentInteractionControllerDelegate {
  private var interactionController: UIDocumentInteractionController?

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
    let controller = UIDocumentInteractionController(url: url)
    controller.delegate = self
    if let mimeType = mimeType, #available(iOS 14.0, *),
      let utType = UTType(mimeType: mimeType)
    {
      controller.uti = utType.identifier
    }
    self.interactionController = controller

    guard let presenter = ShareChannel.topViewController() else {
      return NativeOpenResultMessage(success: false, message: "No presenting view controller")
    }
    let opened = controller.presentPreview(animated: true)
    if opened {
      return NativeOpenResultMessage(success: true, message: nil)
    } else {
      let didOpenMenu = controller.presentOptionsMenu(
        from: presenter.view.bounds, in: presenter.view, animated: true)
      return NativeOpenResultMessage(success: didOpenMenu, message: nil)
    }
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    ShareChannel.topViewController() ?? UIViewController()
  }
}
