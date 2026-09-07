## 0.0.1-dev.2

* Fix: `AudioChannel.load` could throw a synchronous exception from
  `MediaPlayer.setDataSource`/`.prepareAsync` (e.g. a malformed path/URI)
  before `setOnErrorListener`'s callback ever had a chance to fire — so
  the Dart-side status stream never saw `"error"` for that specific
  failure, leaving `attachment_engine`'s audio renderer stuck showing
  normal (unplayed) controls instead of its error/Retry UI. The catch
  block now emits `"error"` before rethrowing, matching
  `VideoPlatformView`'s (and `attachment_engine_ios`'s `AudioChannel`'s)
  existing behavior.

## 0.0.1-dev.1

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
