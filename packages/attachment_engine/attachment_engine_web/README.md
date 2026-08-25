# attachment_engine_web

The web implementation of [`attachment_engine`](../attachment_engine).

## Status

**Development preview — not feature-complete.** Uses only raw
`dart:js_interop` and `dart:ui_web` — Dart SDK core libraries, not even a
pub package, let alone a third-party plugin:

- **Share** (`shareText`) — the browser's native
  [Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API)
  (`navigator.share`)
- **Open externally** (`openExternally`, and `openOfficePreview` falling
  back to it) — `window.open`
- **Paths** (`getApplicationSupportDirectory`, `getApplicationCacheDirectory`)
  — the browser's real
  [Origin Private File System](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)
  (OPFS), via `navigator.storage.getDirectory()`
- **Download** (`startDownload`, `resumeDownload`, `cancelDownload`,
  `downloadEvents`) — `fetch()` streamed chunk-by-chunk into OPFS, with an
  `AbortController` backing cancellation
- **Video/audio playback** (`video*`/`audio*`) — real `<video>`/`<audio>`
  elements, driven directly via `dart:js_interop`, with the video surface
  embedded through `dart:ui_web`'s `platformViewRegistry`

### Paths on web — read this before relying on the returned strings

The browser sandbox has **no real absolute filesystem path** the way
native platforms do. `getApplicationSupportDirectory()` and
`getApplicationCacheDirectory()` return a **stable logical key** —
`/attachment_engine/support` and `/attachment_engine/cache` respectively —
**not a real OS path**. It is only meaningful to this package's own
implementation: `startDownload`/`resumeDownload` interpret any path built
by joining one of these keys with `/` and a filename as a slash-separated
chain of OPFS directory names (created on demand), and write the
downloaded bytes there. Treat the returned string as an opaque handle to
pass back into this same implementation — do not display it to users or
hand it to unrelated APIs expecting a real filesystem path.

### Download implementation notes

`fetch()` does not expose progress natively; this implementation reads
`response.body` via a `ReadableStreamDefaultReader` chunk by chunk,
writing each chunk into an OPFS `FileSystemWritableFileStream` at an
explicit position (so both fresh downloads and `Range`-resumed downloads
land in the right place), and emits a `progress` event
(`{downloadId, type: 'progress', received, total, path}`) after every
chunk — matching the same event shape used by the other platforms
(compare `attachment_engine_windows`'s `HttpClient`-based implementation).
`cancelDownload` aborts the in-flight `fetch()` via a real
[`AbortController`](https://developer.mozilla.org/en-US/docs/Web/API/AbortController).

### Video/audio implementation notes

`videoBuildView` registers one `HtmlElementView` view factory per
`playerId` (via `dart:ui_web`'s `platformViewRegistry.registerViewFactory`)
that returns the same `<video>` DOM element the control methods
(`videoPlay`/`videoPause`/`videoSeek`/…) act on directly, so control calls
and the rendered view always stay in sync. Playback-state events
(`timeupdate`, `playing`, `pause`, `waiting`, `ended`, `error`,
`loadedmetadata`) are forwarded as `{state, positionMs, durationMs, width,
height}` maps (video) or `{state, positionMs, durationMs}` (audio),
matching the shape emitted by the iOS (`VideoPlatformView.swift`/
`AudioChannel.swift`) and Android implementations. Audio has no visual
surface, matching the other platforms — there is no `audioBuildView`.

## Not yet implemented (throws `UnimplementedError`)

- **`shareFile`** — the Web Share API needs an in-memory `File`/`Blob`,
  not a filesystem path; this platform interface's path-based contract
  doesn't carry that. Sharing an actual file needs a byte-based contract
  addition.
- **`pdfOpen`/`pdfRenderPage`/`pdfClose`** — deliberately left
  unimplemented rather than forced in. The task explicitly authorized
  using [PDF.js](https://mozilla.github.io/pdf.js/) (Mozilla's PDF
  renderer) as a one-off exception to this repo's otherwise-strict
  "`flutter.dev`/`dart.dev`-published or SDK-core dependencies only"
  rule, since PDF.js is neither. After investigation, wiring it in
  cleanly turned out to be substantially riskier than the other three
  capabilities, for concrete reasons:
  - PDF.js's worker (`pdf.worker.mjs`) must be reachable at a URL the main
    thread can hand to `pdfjsLib.GlobalWorkerOptions.workerSrc` *before*
    `getDocument()` is called. Vendoring the library files as Dart
    package assets (`lib/assets/…`) does not by itself make them
    fetchable by the browser at a stable, predictable URL — Flutter web
    plugin assets only land under `assets/packages/<pkg>/…` in the final
    build output, and there is no supported way for a plugin's Dart code
    to guarantee the *consuming app's* `index.html` has already loaded
    `pdf.js` (as a `<script>` tag) before this package's Dart code runs,
    short of asking every consuming app to hand-edit their
    `web/index.html` — which defeats the "just add the dependency"
    ergonomics the other three capabilities have.
  - That leaves runtime script-injection (creating a `<script src=...>`
    tag from Dart and awaiting its `load` event) as the only
    fully-automatic option, which adds a real source of flakiness
    (asset-serving path assumptions, load-order races with the worker
    script, and behavior differing between `flutter run -d chrome` and a
    real `flutter build web` release bundle) that could not be verified
    end-to-end in this environment (no Chrome/chromedriver available here
    to actually exercise a rendered PDF page).
  - Given the choice between shipping something fragile and undertested
    for PDF versus keeping the other three capabilities solid, PDF was
    left as a documented follow-up. A future implementation should
    either (a) vendor `pdf.js`/`pdf.worker.mjs` under
    `lib/assets/pdfjs/`, declare them in `flutter: assets:`, and inject a
    `<script>` tag pointing at the built asset path with a `Completer`
    awaiting its `load` event before calling `pdfjsLib.getDocument`, or
    (b) document that the consuming app must add the PDF.js `<script>`
    tag to its own `web/index.html` (the same convention used by plugins
    that wrap a JS library requiring page-load-time setup) — and pick
    whichever is verified against a real browser.
- **Embedded webview** — out of scope for every platform in this
  contract; handled by the official `webview_flutter` package at the
  app-facing layer instead.

You should not need to depend on this package directly — add
[`attachment_engine`](../attachment_engine) to your app instead, and the
right platform implementation is selected automatically.
