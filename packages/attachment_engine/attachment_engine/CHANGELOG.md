## 0.0.1-dev.1

Initial real release, after a full native rewrite and hardening pass.

* Fully-native platform channels for PDF, video, audio, webview, share,
  open-externally, download, and paths — no third-party plugin
  dependencies. Minimal pub deps: `plugin_platform_interface`, `crypto`,
  `meta`, `equatable`.
* Pure-Dart JSON-file metadata store and hand-written ZIP reader (no
  Hive/`archive` dependency).
* Attachment resolve → cache (LRU, checksum-verified) → download → render
  pipeline with in-flight request de-duplication and typed
  `AttachmentFailure`s.
* HTTP range-based download resume on both platforms: Android
  (`HttpURLConnection` + `Range` header + `.part.meta` sidecar), iOS
  (`URLSessionDownloadTask` resume-data). Falls back to a clean full
  restart when the server/OS doesn't support resuming.
* HLS (`.m3u8`) adaptive playback works on both platforms via native APIs
  (`AVPlayer` on iOS, `MediaPlayer` on Android). DASH (`.mpd`) is not
  supported — documented limitation of avoiding ExoPlayer/Media3.
* Security: zip-slip-safe archive extraction, hashed (never raw) cache
  filenames, no URLs/tokens ever logged, stable cache identity independent
  of rotating signed URLs.
* Widgets: `AttachmentTile`, `AttachmentErrorView`, `AttachmentList`,
  `AttachmentViewer`.
* CI: GitHub Actions running format/analyze/test/Android build on
  `ubuntu-latest` and an iOS build job on `macos-latest`.
