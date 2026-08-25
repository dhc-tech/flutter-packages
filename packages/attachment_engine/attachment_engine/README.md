# attachment_engine

A universal, reusable Flutter plugin for handling **every** attachment
concern an app is likely to need: metadata modeling, format detection,
resolution (local/cache/network), caching with LRU eviction, downloading
with retry, concurrency dedup, capability derivation, full-screen viewing
and lightweight previewing, playback (video/audio), PDF/HTML/text
rendering, office/archive/SCORM handling via pluggable strategies, sharing,
external "open with", and cache/storage management.

This is a fresh, standalone package. **There is no existing host app** at
the time this plugin was built, so any statement about "migrating"
Course/Assessments/etc. features from a host app is **not applicable** —
that migration work starts only once a real app adopts this plugin.

## Architecture

```
                         ┌─────────────────────────┐
                         │     AttachmentManager    │  <- public facade
                         │ open/preview/download/   │
                         │ play/retry/share/openExt │
                         └────────────┬─────────────┘
                                      │
                 ┌────────────────────┼─────────────────────┐
                 ▼                    ▼                     ▼
       ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐
       │ AttachmentResolver│  │ CapabilityEngine │  │ AttachmentDiagnostics│
       │ validate->local?  │  │ derives actions  │  │ Sink (host-pluggable)│
       │ ->cache?->network?│  └──────────────────┘  └────────────────────┘
       └─────────┬─────────┘
                  │ dedups via InFlightRegistry (stable logical key)
     ┌────────────┼─────────────────┐
     ▼            ▼                 ▼
┌─────────┐ ┌────────────────┐ ┌───────────────────┐
│FileSource│ │AttachmentCache │ │  DownloadManager   │
│BytesSrc  │ │Manager (LRU,   │ │ (dio-backed,       │
└─────────┘ │ HiveMetadata   │ │  retry, progress)  │
             │ Store)         │ └───────────────────┘
             └────────────────┘

FormatDetector: explicit mime > magic bytes > extension > url ext > http content-type
                          │
                          ▼
                 AttachmentType (image/pdf/office/text/html/scorm/h5p/video/audio/archive/unknown)
                          │
                          ▼
            RendererRegistry -> per-type AttachmentRenderer
   (image/pdf/video/audio/html/text/scorm/office/archive/unknown)
```

### Lifecycle

```
discovered -> validating -> resolving -> (cached | downloading -> cached) -> ready -> rendering
                                                     │
                                                     ▼
                                                  failed / expired
                                                     │
                                                     ▼
                                                  cleaned (cache removed)
```

## Quickstart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AttachmentManager.initializeDefault();
  runApp(const MyApp());
}

// Full viewer
AttachmentViewer(attachment: resolvedAttachment);

// Lightweight preview (never instantiates a video/audio/pdf controller)
AttachmentPreview(attachment: attachment);

// Resolve + open programmatically
final resolved = await AttachmentManager.instance.open(attachment);
await AttachmentManager.instance.share(resolved.attachment);
```

`AttachmentTile` / `AttachmentList` / `AttachmentGrid` provide ready-made
list/grid UI wired to `AttachmentActions` (share/download/open/delete,
driven by `AttachmentCapabilities`) and `AttachmentErrorView` (maps
`AttachmentFailure` to a friendly message + retry button).

## Configuration

`AttachmentEngineConfig` is an immutable, `Equatable`-based configuration
object composed of five sub-configs: `CacheConfig`, `RendererConfig`,
`DownloadConfig`, `PreviewConfig` and `ExternalOpenConfig`.
`AttachmentEngineConfig.defaults()` (also the default value used when no
config is supplied) reproduces the engine's pre-existing behavior exactly:
caching on with a 500MB LRU cap, every renderer enabled, 3 retries,
resume enabled, and external-open fallback enabled. Pass a config to
`AttachmentManager.initializeDefault`:

```dart
await AttachmentManager.initializeDefault(
  config: AttachmentEngineConfig(
    cache: const CacheConfig(maxTotalSizeBytes: 100 * 1024 * 1024),
    renderers: const RendererConfig(video: false),
    download: const DownloadConfig(maxConcurrentDownloads: 2),
  ),
);
```

Invalid values (negative sizes, zero/negative concurrency, negative
retries, non-positive timeouts, negative retention, or
`maxFileSizeBytes > maxTotalSizeBytes`) throw
`AttachmentConfigValidationError` (an `ArgumentError`) at construction or
validation time.

### Cache (`CacheConfig`)

```dart
const CacheConfig(
  enabled: true,               // false: no cache dir, no writes, no metadata, no eviction
  maxTotalSizeBytes: 500 * 1024 * 1024, // LRU cap, reuses CachePolicy
  maxFileSizeBytes: 20 * 1024 * 1024,   // oversized files skip the persistent cache
  retention: Duration(days: 7),          // entries older than this are treated as a miss
  thumbnailCachingEnabled: true,
  previewCachingEnabled: true,
);
```
When `enabled` is false, local files still resolve directly and remote
attachments are fetched fresh every time; going offline in that mode
surfaces the existing `NetworkUnavailable` failure rather than silently
consulting a cache that doesn't exist.

### Renderers (`RendererConfig`)

```dart
const RendererConfig(video: false, archive: false); // all others stay enabled by default
```
A disabled type never crashes and is never silently rendered by a
different renderer: `RendererRegistry`/`CapabilityEngine` report it as
disabled (`AttachmentCapabilities.rendererDisabledByConfig == true`,
`canPreview`/`canPlay`/`canOpen == false`) and the UI falls back to the
same generic "unsupported" surface used for genuinely unknown formats.
HLS/adaptive video is part of the `video` flag — there is no separate
toggle for it, since it isn't a distinct `AttachmentType`.

### Download (`DownloadConfig`)

```dart
const DownloadConfig(
  connectTimeout: Duration(seconds: 15),
  receiveTimeout: Duration(seconds: 30),
  maxRetries: 3,
  retryBackoff: DownloadRetryBackoff.exponential,
  retryBaseDelay: Duration(milliseconds: 500),
  maxConcurrentDownloads: 3,
  resumeEnabled: true,
);
```
`connectTimeout + receiveTimeout` is enforced as a single per-attempt
wall-clock timeout (the native transport doesn't expose a distinct
connect phase). `maxConcurrentDownloads` is a real cap enforced by
`DownloadManager` with a wait queue — previously downloads were
unbounded, so this is a deliberate, documented behavior change from
"unlimited" to "capped at 3" by default.

### Preview (`PreviewConfig`)

```dart
const PreviewConfig(
  thumbnailsEnabled: true,
  lazyLoading: true,
  preloadPolicy: PreviewPreloadPolicy.none, // none | adjacent | all
);
```
`preloadPolicy` records host intent; the engine does not yet walk lists to
preload automatically, so `adjacent`/`all` are meaningful only if the host
app implements its own preloading loop on top of `AttachmentManager.preview`.

### External open (`ExternalOpenConfig`)

```dart
const ExternalOpenConfig(allowExternalFallback: false);
```
When false, `AttachmentManager.openExternally` throws `ExternalOpenDisabled`,
`AttachmentCapabilities.canOpenExternally` is false, the generic
unknown/disabled-renderer widget shows a disabled message instead of an
"Open externally" affordance, and Office documents on Android (which have
no in-app viewer) report the same disabled state instead of opening
externally.

### Media

No `MediaConfig` is provided. The native video/audio channels
(`NativeVideoController`/`NativeAudioController` and their Swift/Kotlin
counterparts) do not currently expose autoplay, loop, controls-visibility
or fullscreen toggles, so no such config was added — it would have been a
decorative flag with no effect.

## Dependency choices: fully-native architecture

This plugin does **not** wrap third-party federated plugins for any
platform capability. Every capability that needs OS access is implemented
as a small, hand-written Kotlin (Android) / Swift (iOS/macOS) native
implementation, under `lib/src/native/`. Every request/response call
(PDF, audio/video control, share, open-externally, office preview, paths,
download start/resume/cancel) is dispatched through a
[pigeon](https://pub.dev/packages/pigeon)-generated type-safe `HostApi`
(schema in `attachment_engine_platform_interface/pigeons/messages.dart`)
instead of hand-written `MethodChannel` string dispatch; the
audio/video/download *event streams* remain hand-written `EventChannel`s,
since Pigeon's event-channel support doesn't cleanly express a channel
name keyed by a `playerId` chosen dynamically at runtime (see the note at
the top of that schema file). The only remaining Dart dependencies are
pure-Dart/Flutter-SDK ones with no native platform surface of their own:

| Package | Why it's still a dependency |
|---|---|
| `plugin_platform_interface` | Required scaffolding for a Flutter federated-plugin-shaped package (even though this plugin has no separate platform-interface package split). |
| `crypto` | SHA-256 for cache-key hashing (never store raw filenames) and content checksums. Pure Dart, no native code. |
| `meta`, `equatable` | Value-type ergonomics (`@immutable`-adjacent annotations, structural equality) without code generation. Pure Dart. |
| `mocktail`, `test`, `flutter_test`, `flutter_lints` (dev only) | Mocking/fakes, pure-Dart test running, and lint rules. Not shipped in the built plugin. |

Capabilities previously provided by third-party plugins are now backed by
platform APIs directly, one Pigeon `HostApi` (control) plus, where noted,
one hand-written `EventChannel` (streamed state) per capability:

| Capability | Dart wrapper | Android (Kotlin) | iOS (Swift) | Transport |
|---|---|---|---|---|
| PDF rendering | `NativePdfController` | `android.graphics.pdf.PdfRenderer` — opens a PDF by fd and renders pages to PNG bitmaps. | PDFKit (`PDFDocument`, `PDFPage.thumbnail`). | `PdfHostApi` (open/renderPage/close) |
| Video playback | `NativeVideoController` | `android.media.MediaPlayer` rendering into a `TextureView` via a `PlatformView`/`AndroidView`. | `AVPlayer` rendering into an `AVPlayerLayer` via a `FlutterPlatformView`/`UiKitView`. | `VideoHostApi` (control) + `attachment_engine/video_events/{playerId}` (state, hand-written `EventChannel`) + `attachment_engine/video_view` (platform view) |
| Audio playback | `NativeAudioController` | `android.media.MediaPlayer` for both local files and streaming URLs. | `AVAudioPlayer` for local files, `AVPlayer` for streaming remote URLs. | `AudioHostApi` (control) + `attachment_engine/audio_events/{playerId}` (state, hand-written `EventChannel`) |
| WebView (HTML/SCORM/H5P entry point) | `WebViewController`/`WebViewWidget` from the official [`webview_flutter`](https://pub.dev/packages/webview_flutter) package (`flutter.dev`-published) — no hand-written native channel for this one capability; `webview_flutter_android`/`webview_flutter_wkwebview` handle it uniformly. `loadFile(path)` for offline/cached HTML, `loadRequest(Uri)` for remote. | n/a (handled by `webview_flutter_android`) | n/a (handled by `webview_flutter_wkwebview`, also covers macOS) | n/a |
| Share | `NativeShareChannel` | `Intent.ACTION_SEND` with a `FileProvider` content URI. | `UIActivityViewController`. | `ShareHostApi` (shareFile/shareText) |
| Open externally | `NativeOpenChannel` | `Intent.ACTION_VIEW` with a `FileProvider` content URI, inferred MIME type, and `grantUriPermission`. | `UIDocumentInteractionController` preview/options-menu presentation. | `OpenHostApi` (openExternally) |
| Download | `NativeDownloadClient` (implements `DownloadClient`, used by `DownloadManager`) | `HttpURLConnection`, streaming progress over an `EventChannel`. | `URLSession`/`URLSessionDownloadTask`, streaming progress via `URLSessionDownloadDelegate` over the same `EventChannel` shape. | `DownloadHostApi` (start/resume/cancel) + `attachment_engine/download_events` (progress/completion/error, tagged by `downloadId`, hand-written `EventChannel`) |
| App-private paths | `NativePathsChannel` | `context.filesDir` / `context.cacheDir`. | `NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory / .cachesDirectory, .userDomainMask, true)`. | `PathsHostApi` (getApplicationSupportDirectory/getApplicationCacheDirectory) |
| Cache metadata store | `FileBasedMetadataStore` (`AttachmentMetadataStore` impl) | Pure Dart, backed by a JSON index file under the app-private cache directory — no native/Hive dependency. | Same (pure Dart). | n/a |
| Zip/SCORM archive reading | `ZipReader` | Pure Dart, hand-written ZIP central-directory parser + `dart:io`'s `ZLibDecoder` for DEFLATE — no native/`archive` package dependency. | Same (pure Dart). | n/a |

### Simplifications vs. full native parity

- **Video/audio use `MediaPlayer`/`AVPlayer`/`AVAudioPlayer`, not
  ExoPlayer/Media3.** This avoids pulling in additional Gradle
  dependencies. HLS (`.m3u8`) adaptive streaming works on both platforms
  using only native APIs (`AVPlayer` on iOS supports HLS natively;
  `MediaPlayer` has had built-in HLS support since API 16) — no extra code
  was needed beyond passing the `.m3u8` URL straight to
  `setDataSource`/`AVPlayerItem(url:)`, which the implementation already
  did. **DASH (`.mpd`) is genuinely unsupported** — plain `MediaPlayer` has
  no DASH support, and there is no native iOS/Android DASH API either; this
  is a real limitation of avoiding ExoPlayer/Media3, not an oversight. See
  "Supported formats & known limitations" below.
- **The embedded video view has no built-in playback chrome** (no native
  transport controls overlay); Dart-side UI is expected to drive
  play/pause/seek via `NativeVideoController`.
- **"Open externally" on iOS** uses `UIDocumentInteractionController`
  (preview, falling back to its options menu) rather than a UTI-registered
  document picker/QuickLook flow, which is a close but not pixel-identical
  analogue of Android's `ACTION_VIEW` chooser.
- **Downloads resume from a partial byte range** on both platforms:
  Android uses `HttpURLConnection` with a `Range: bytes=N-` header plus a
  small `.part.meta` sidecar file recording the source URL (so a stale or
  foreign partial file is never appended to); iOS uses
  `URLSessionDownloadTask`'s native resume-data
  (`cancel(byProducingResumeData:)` → `downloadTask(withResumeData:)`),
  persisted to a `.resumedata` sidecar file. `DownloadManager` passes
  `resume: true` automatically from the second retry attempt onward. If the
  server ignores the `Range` header (responds `200` instead of `206`) or
  iOS's resume-data is invalid/expired, both platforms fall back to a full
  clean restart rather than corrupting the destination file.

### Bringing your own metadata store (ObjectBox, etc.)

`AttachmentMetadataStore` is the persistence seam:

```dart
abstract class AttachmentMetadataStore {
  Future<void> init();
  Future<CacheEntry?> get(String key);
  Future<List<CacheEntry>> getAll();
  Future<void> put(CacheEntry entry);
  Future<void> delete(String key);
  Future<void> clear();
}
```

A host app with ObjectBox already set up should implement this interface
against its own ObjectBox entities/boxes and pass it into
`AttachmentCacheManager(metadataStore: MyObjectBoxStore())` instead of using
the bundled `FileBasedMetadataStore` (a pure-Dart, JSON-file-backed default
with no native or third-party database dependency).

## Security notes

- **No URLs or tokens in logs.** `AttachmentDiagnosticsSink` methods only
  ever receive ids, durations, sizes and error *type names* — never a raw
  URL. Where a URL must be surfaced for debugging, `sanitizeForLog()`
  strips the query string (where signed-URL params/tokens live) before use.
- **Cache identity is never the remote URL.** `Attachment.stableIdentity`
  is `cacheKey ?? id`; signed URLs can rotate freely without invalidating
  or duplicating the cache entry — see `test/cache_key_identity_test.dart`.
- **Cache filenames are hashed, not raw.** `AttachmentCacheManager.sanitizedFileName`
  SHA-256-hashes the logical key; raw remote filenames and path separators
  never reach the filesystem.
- **Archive extraction is zip-slip-safe.** `extractArchiveSafely` (in
  `archive_renderer.dart`, reused by `scorm_renderer.dart`) rejects any
  entry containing `..`, an absolute path, or a symlink, and re-verifies
  the resolved output path stays under the target directory before writing
  a single byte.
- **Best-effort content validation.** After download, `AttachmentResolver`
  re-detects the type from magic bytes and treats a confident mismatch
  against the declared type as `CorruptedFile`.

## Supported formats & known limitations

| Media | HLS (`.m3u8`) | DASH (`.mpd`) | Progressive (mp4/mp3/wav/etc.) |
|---|---|---|---|
| Android (`MediaPlayer`) | Supported (native since API 16) | **Not supported** — no DASH support without ExoPlayer/Media3, which is intentionally excluded | Supported |
| iOS (`AVPlayer`) | Supported (native AVFoundation) | **Not supported** — no native DASH decoder in AVFoundation | Supported |

If a host app needs DASH, the documented exception is to reintroduce a
dedicated media engine (ExoPlayer/Media3 on Android; a third-party DASH
player on iOS) behind the same `NativeVideoController`/`NativeAudioController`
interface — this plugin deliberately does not do so by default to keep the
native/Gradle dependency surface minimal.

## Known limitations

- **HTTP range download resume is best-effort, not guaranteed.** It relies
  on the server honoring `Range` requests (Android) or the OS retaining
  valid resume-data (iOS, which can expire/invalidate e.g. if the temp file
  was cleaned up) — see "Downloads resume from a partial byte range" above.
  When unsupported, both platforms cleanly restart rather than corrupting
  output, but do not resume.
- **No full H5P runtime is bundled.** `AttachmentType.h5p` is detected, but
  rendering requires a host-provided H5P player HTML bundle loaded through
  `HtmlAttachmentRenderer` — there is no bundled H5P JS runtime.
- **No SCORM RTE / tracking.** `ScormAttachmentRenderer` safely extracts a
  SCORM zip and launches its entry HTML, but does not implement a SCORM
  API adapter (`cmi.*` tracking calls) — there is no LMS/server yet to
  report to.
- **Office document preview is intentionally asymmetric by platform.**
  `OfficeAttachmentRenderer` has no bundled Office renderer/conversion
  server, so it defers to the platform:
  - **iOS**: a genuine in-app preview via `QLPreviewController`
    (QuickLook) — an Apple system framework, zero third-party dependency —
    presented modally over the Flutter view. `canPreview` is `true`.
  - **Android**: no in-app Office viewer exists on the platform, so it
    falls back to `NativeOpenChannel`'s external-open flow
    (`Intent.ACTION_VIEW` + `FileProvider`). `canPreview` is `false` and
    `canOpenExternally` is `true`. This is a documented platform
    limitation, not a bug.

  `OfficeConversionStrategy` remains the extension point a host app can
  implement once it has server-side or on-device conversion available, and
  is honored on both platforms when supplied.
- **Video/audio playback uses `MediaPlayer` (Android) / `AVPlayer` /
  `AVAudioPlayer` (iOS), not ExoPlayer/Media3.** HLS works; DASH does not —
  see "Supported formats & known limitations" above.
- **ObjectBox is not integrated** (there is no existing ObjectBox setup in
  this fresh project). `FileBasedMetadataStore` is the bundled default;
  swap in an ObjectBox-backed `AttachmentMetadataStore` implementation in a
  host app that already depends on ObjectBox.
- **Course/Assessments/etc. migration is N/A.** No host app exists yet to
  migrate from; this section will apply once the plugin is adopted into a
  real app.

## Testing

`flutter test` covers: format detection priority + magic bytes, cache key
stability across rotated signed URLs, in-flight request dedup (N
concurrent callers → 1 underlying call), LRU cache eviction, failure
message mapping + localization override hook, capability derivation per
type/status, `DownloadManager` retry/progress against a fake
`DownloadClient` (no real network calls), and widget tests for
`AttachmentTile` (loading/ready/error states) and `AttachmentErrorView`
(retry button + callback).

## Example app

`example/lib/main.dart` lists four sample attachments (a network image, a
network PDF, a network MP4, and a network MP3) via `AttachmentList`;
tapping one resolves it through `AttachmentManager` and opens it in
`AttachmentViewer`, exercising the full resolve → cache → download →
render pipeline end-to-end.
