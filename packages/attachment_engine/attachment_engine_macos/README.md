# attachment_engine_macos

The macOS implementation of [`attachment_engine`](../attachment_engine),
backed entirely by native Swift code — **no third-party plugin
dependencies**.

## Status

Full feature parity with iOS/Android, native (see
`macos/attachment_engine_macos/Sources/attachment_engine_macos/`). Every
request/response call goes through a
[pigeon](https://pub.dev/packages/pigeon)-generated `HostApi` protocol
(schema: `attachment_engine_platform_interface/pigeons/messages.dart`,
generated bindings: `Messages.g.swift`); audio/video/download *events*
stay on hand-written `FlutterEventChannel`s, noted per-row below:

- **PDF** — PDFKit (`PDFDocument`, `PDFPage.thumbnail`), via `PdfHostApi`
- **Audio** — AVFoundation (`AVAudioPlayer` for local files, `AVPlayer` for
  streaming URLs); control via `AudioHostApi`, playback events via a
  hand-written per-player `FlutterEventChannel`
- **Video** — AVKit (`AVPlayerLayer`), embedded via a
  `FlutterPlatformViewFactory` — surfaced to Dart through `AppKitView`;
  control via `VideoHostApi`, playback events via a hand-written
  per-player `FlutterEventChannel`
- **WebView** — `WKWebView`, embedded the same way
- **Paths** — `NSSearchPathForDirectoriesInDomains`, via `PathsHostApi`
- **Share** — `NSSharingServicePicker` (AppKit's native share sheet), via
  `ShareHostApi`
- **Open externally** — `NSWorkspace.open(_:)`, via `OpenHostApi`
- **Office preview** — `QLPreviewPanel` (QuickLook; doc/docx/xls/xlsx/ppt/
  pptx/rtf and more, ships with every macOS install), via `OfficeHostApi`
- **Download** — `URLSession`/`URLSessionDownloadTask`, with resume-data
  support; start/resume/cancel via `DownloadHostApi`, progress events via
  a hand-written shared `FlutterEventChannel`

Registers as a Swift Package (`Package.swift`) — Flutter reports
`All plugins found for macos are Swift Packages`. A `.podspec` is kept
alongside it for CocoaPods-only consumers, per Flutter's dual-support
requirement during the SPM migration window.

You should not need to depend on this package directly — add
[`attachment_engine`](../attachment_engine) to your app instead, and the
right platform implementation is selected automatically.
