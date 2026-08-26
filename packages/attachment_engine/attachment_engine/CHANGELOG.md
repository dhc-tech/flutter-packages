## 0.0.1-dev.2

* `AttachmentViewer` now auto-resolves an unresolved `Attachment`
  internally (via `AttachmentManager.instance.open` by default,
  overridable), showing loading/error states — callers no longer need to
  pre-resolve before constructing it.
* `AttachmentManager.initializeDefault()` accepts an optional
  `downloadClient`/`connectivityChecker` so a host app can route
  downloads through its own auth-aware HTTP client.
* New `AttachmentType.csv` with `CsvAttachmentRenderer` (RFC 4180-style
  parsing, rendered as a table) — `.csv`/`.tsv` (auto-detected delimiter)
  are no longer misclassified as plain text.
* `PdfAttachmentRenderer` remembers the last-viewed page per attachment
  (`PdfPageMemory`, session-scoped by default, overridable/persistable)
  and shows a retry affordance on open/page-render failure.
* `OfficeAttachmentRenderer` now prefers in-app viewing at every step,
  external-open only as the genuine last resort: iOS QuickLook → bundled
  genuinely-offline in-app renderers on Android (`.docx` via
  `OfflineDocxViewer`, `.xlsx`/`.xls`/`.xlsm` via
  `OfflineSpreadsheetViewer`, `.pptx` via `OfflinePptxViewer` — all
  zero-network, bundled open-source JS libraries, see
  `assets/office_offline/README.md`) → Microsoft Office Online (needs a
  connection) → optional `conversionStrategy` (deprioritized, lossy) →
  external-open. Legacy `.doc`/`.ppt` and OpenDocument formats remain
  uncovered by an offline renderer — documented, deliberate gap (no
  suitable renderer exists for the former; the only option for the
  latter, WebODF, is AGPL-licensed).
* `TextAttachmentRenderer`'s full (non-snippet) view now has an in-file
  search bar (case-insensitive, match counter, next/previous navigation)
  — set `showSearch: false` to opt out.
* `.xlsm` is now classified as `AttachmentType.office` (was falling
  through to a generic mime lookup).
* Minimum Dart SDK raised to `^3.13.0` (dot-shorthand syntax used
  throughout the renderers).

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
