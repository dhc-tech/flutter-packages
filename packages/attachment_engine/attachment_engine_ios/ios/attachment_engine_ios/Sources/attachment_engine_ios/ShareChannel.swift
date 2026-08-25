import Flutter
import UIKit

/// Replaces `share_plus`. Uses `UIActivityViewController`. Implements the
/// Pigeon-generated `ShareHostApi`.
class ShareChannel: NSObject, ShareHostApi {
  func register(with messenger: FlutterBinaryMessenger) {
    ShareHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    ShareHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
  }

  @MainActor
  func shareFile(path: String, text: String?) async throws {
    var items: [Any] = [URL(fileURLWithPath: path)]
    if let text = text { items.append(text) }
    try presentActivity(items: items)
  }

  @MainActor
  func shareText(text: String) async throws {
    try presentActivity(items: [text])
  }

  @MainActor
  private func presentActivity(items: [Any]) throws {
    guard let presenter = ShareChannel.topViewController() else {
      throw PigeonError(code: "share_failed", message: "No presenting view controller", details: nil)
    }
    let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let popover = activityVC.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    presenter.present(activityVC, animated: true, completion: nil)
  }

  static func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?.rootViewController
  ) -> UIViewController? {
    if let nav = base as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
      return topViewController(base: selected)
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }
}
