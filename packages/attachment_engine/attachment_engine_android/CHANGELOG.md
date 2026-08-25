## 0.0.1-dev.0

* Initial release: the Android implementation extracted from
  `attachment_engine` 0.1.0 as part of the federated-plugin split. Implements
  `AttachmentEnginePlatform` from `attachment_engine_platform_interface` on
  top of hand-written Kotlin (Media3/ExoPlayer, `PdfRenderer`, `WebView`,
  `HttpURLConnection`-based resumable download, `FileProvider`-based
  share/open).
* Migrates every request/response native call (PDF, audio/video control,
  share, open-externally, paths, download start/resume/cancel) from
  hand-written `MethodChannel` string dispatch to the
  [pigeon](https://pub.dev/packages/pigeon)-generated `HostApi`s in
  `attachment_engine_platform_interface` (`Messages.g.kt`). The
  audio/video/download event streams are unchanged, hand-written
  `EventChannel`s.
