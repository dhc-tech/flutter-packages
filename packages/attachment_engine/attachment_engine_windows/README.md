# attachment_engine_windows

The Windows implementation of [`attachment_engine`](../attachment_engine).

## Status

**Development preview — not feature-complete, and the native (C++) code
described below has NOT been build-verified.** This machine has no
Windows compiler (`cl.exe`/`msbuild`) available, and
`flutter create --platforms=windows` refuses to scaffold a native template
here, so the C++ files under `windows/` could not be compiled or even
syntax-checked in this environment. They were written to closely mirror
official Microsoft documentation and the same channel-name/method/event
contract already proven out by the working Android (Kotlin) and iOS
(Swift) implementations — but they are **"written, not yet build-verified"**
and need a real Windows build (local machine or CI) to confirm.

### Pure Dart (verified — `flutter analyze`/`dart format`/`flutter test` all pass)

- **Paths** (`getApplicationSupportDirectory`, `getApplicationCacheDirectory`)
  — via `path_provider` (`flutter.dev`-published, official)
- **Open externally** (`openExternally`, and `openOfficePreview` falling
  back to it) — via `url_launcher` (`flutter.dev`-published, official)
- **Download** (`startDownload`, `resumeDownload`, `cancelDownload`,
  `downloadEvents`) — via `dart:io`'s built-in `HttpClient`, with
  `Range`-header resume support

### Native (unverified by build — see `windows/*.cpp`/`*.h` header comments)

- **Share** (`shareFile`, `shareText`) — `windows/share_channel.cpp`, using
  the documented `IDataTransferManagerInterop`/`DataTransferManager` COM
  API to show the real Windows share flyout from this app's top-level
  HWND:
  https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-idatatransfermanagerinterop
- **Audio playback** (`audioLoad`/`audioPlay`/`audioPause`/`audioSeek`/
  `audioSetSpeed`/`audioSetVolume`/`audioDispose`/`audioEvents`) —
  `windows/audio_channel.cpp`, using Media Foundation's `IMFMediaEngine`:
  https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nn-mfmediaengine-imfmediaengine
- **Video playback + embedding** (same method shape as audio, plus
  `videoBuildView`) — `windows/video_channel.cpp`, same `IMFMediaEngine`
  API, rendering to a child HWND (`MF_MEDIA_ENGINE_PLAYBACK_HWND`) that the
  Dart-side widget keeps positioned via an explicit `setLayout` call. This
  is a documented, functional tradeoff versus true Flutter compositing —
  see the "Embedding tradeoff" comment in `windows/video_channel.h` for
  why, and what a fuller frame-server + `TextureRegistrar` implementation
  would look like instead.

Still not yet implemented (throws `UnimplementedError`):

- **PDF native rendering** and **embedded native webview surfaces** — no
  native-view integration has been wired up for either yet.

You should not need to depend on this package directly — add
[`attachment_engine`](../attachment_engine) to your app instead, and the
right platform implementation is selected automatically.
