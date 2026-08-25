## 0.0.1-dev.1

* Initial development release: native Swift implementation of PDF
  (PDFKit), audio (AVFoundation), video (AVKit, embedded via
  `FlutterPlatformViewFactory`/`AppKitView`), webview (`WKWebView`,
  embedded the same way), paths (`NSSearchPathForDirectoriesInDomains`),
  share (`NSSharingServicePicker`), open-externally (`NSWorkspace.open`),
  office preview (`QLPreviewPanel`/QuickLook), and download
  (`URLSession`) — zero third-party plugin dependencies, full feature
  parity with iOS/Android.
* Registered as a Swift Package (`Package.swift`); a `.podspec` is kept
  alongside for CocoaPods-only consumers per Flutter's dual-support
  requirement during the SPM migration window.
* Migrates every request/response native call (PDF, audio/video control,
  share, open-externally, office preview, paths, download
  start/resume/cancel) from hand-written `FlutterMethodChannel` string
  dispatch to the [pigeon](https://pub.dev/packages/pigeon)-generated
  `HostApi` protocols in `attachment_engine_platform_interface`
  (`Messages.g.swift`). The audio/video/download event streams are
  unchanged, hand-written `FlutterEventChannel`s.
