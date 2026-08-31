## 0.0.1-dev.2

* Fixes `openOfficePreview`'s Office/QuickLook `QLPreviewController` modal
  resolving its Dart future as soon as the preview was *presented* instead
  of when the user actually *dismissed* it, leaving callers with no signal
  to react to the close (e.g. to pop the screen behind the now-closed
  modal). It now implements `QLPreviewControllerDelegate` and only
  completes on `previewControllerDidDismiss`.

## 0.0.1-dev.1

* Initial release: the iOS implementation extracted from `attachment_engine`
  0.1.0 as part of the federated-plugin split. Implements
  `AttachmentEnginePlatform` from `attachment_engine_platform_interface` on
  top of hand-written Swift (AVFoundation/AVPlayer, PDFKit, `WKWebView`,
  `URLSessionDownloadTask`-based resumable download,
  `UIDocumentInteractionController`/`UIActivityViewController`-based
  share/open).
* Migrates every request/response native call (PDF, audio/video control,
  share, open-externally, office preview, paths, download
  start/resume/cancel) from hand-written `FlutterMethodChannel` string
  dispatch to the [pigeon](https://pub.dev/packages/pigeon)-generated
  `HostApi` protocols in `attachment_engine_platform_interface`
  (`Messages.g.swift`). The audio/video/download event streams are
  unchanged, hand-written `FlutterEventChannel`s.
