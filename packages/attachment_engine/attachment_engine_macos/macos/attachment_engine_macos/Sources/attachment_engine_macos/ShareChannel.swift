import Cocoa
import FlutterMacOS

/// Uses `NSSharingServicePicker` (AppKit's native share sheet) — the macOS
/// equivalent of iOS's `UIActivityViewController`. Implements the
/// Pigeon-generated `ShareHostApi`.
class ShareChannel: NSObject, ShareHostApi, NSSharingServicePickerDelegate {
  // Kept alive for the duration of the picker's lifetime.
  private var activePicker: NSSharingServicePicker?

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
    try presentPicker(items: items)
  }

  @MainActor
  func shareText(text: String) async throws {
    try presentPicker(items: [text])
  }

  @MainActor
  private func presentPicker(items: [Any]) throws {
    guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first,
      let contentView = window.contentView
    else {
      throw PigeonError(code: "share_failed", message: "No presenting window", details: nil)
    }
    let picker = NSSharingServicePicker(items: items)
    picker.delegate = self
    self.activePicker = picker
    picker.show(
      relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
  }

  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker,
    didChoose service: NSSharingService?
  ) {
    // Release the retained picker once the user has made (or dismissed) a choice.
    DispatchQueue.main.async { [weak self] in
      self?.activePicker = nil
    }
  }
}
