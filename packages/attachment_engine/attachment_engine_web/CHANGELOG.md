## 0.0.1-dev.1

* Initial development release: share (`shareText`, via the Web Share API)
  and open-externally (`window.open`) — via raw `dart:js_interop` (a Dart
  SDK core library, not even a pub package).
* Added paths (`getApplicationSupportDirectory`/
  `getApplicationCacheDirectory`) via the Origin Private File System
  (OPFS, `navigator.storage.getDirectory()`), returning a stable logical
  key rather than a real OS path — see README for details.
* Added download (`startDownload`/`resumeDownload`/`cancelDownload`/
  `downloadEvents`) via `fetch()` streamed chunk-by-chunk into OPFS, with
  `AbortController`-backed cancellation and the same
  `{downloadId, type, received, total, path, message}` event shape used
  by the other platforms.
* Added video/audio playback (`video*`/`audio*`) via real
  `<video>`/`<audio>` elements driven with `dart:js_interop`, with the
  video surface embedded through `dart:ui_web`'s
  `platformViewRegistry.registerViewFactory`, emitting the same
  `{state, positionMs, durationMs, width, height}` (video) /
  `{state, positionMs, durationMs}` (audio) event shape as iOS/Android.
* `shareFile`, PDF native rendering, and embedded webview are still not
  implemented — see README for why (PDF.js integration was investigated
  and deliberately deferred as a documented follow-up rather than forced
  in; webview is out of scope for every platform in this contract).
