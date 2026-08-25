# attachment_engine_linux

The Linux implementation of [`attachment_engine`](../attachment_engine).

## Status

**Development preview — not feature-complete, and the native (C) code
described below has NOT been build-verified.** This machine has no Linux
compiler / `pkg-config` / `gtk+-3.0` dev headers available, and
`flutter create --platforms=linux` refuses to scaffold a native template
here, so the C files under `linux/` could not be compiled or even
syntax-checked in this environment. They were written to closely mirror
official GNOME/GStreamer documentation and the same channel-name/method/
event contract already proven out by the working Android (Kotlin) and iOS
(Swift) implementations — but they are **"written, not yet build-verified"**
and need a real Linux build (local machine or CI) to confirm.

### Pure Dart (verified — `flutter analyze`/`dart format`/`flutter test` all pass)

- **Paths** (`getApplicationSupportDirectory`, `getApplicationCacheDirectory`)
  — via `path_provider` (`flutter.dev`-published, official)
- **Open externally** (`openExternally`, and `openOfficePreview` falling
  back to it) — via `url_launcher` (`flutter.dev`-published, official)
- **Download** (`startDownload`, `resumeDownload`, `cancelDownload`,
  `downloadEvents`) — via `dart:io`'s built-in `HttpClient`, with
  `Range`-header resume support

### Native (unverified by build — see `linux/*.cc`/`*.h` header comments)

- **Audio playback** (`audioLoad`/`audioPlay`/`audioPause`/`audioSeek`/
  `audioSetSpeed`/`audioSetVolume`/`audioDispose`/`audioEvents`) —
  `linux/audio_channel.cc`, using GStreamer's documented `playbin`
  convenience element:
  https://gstreamer.freedesktop.org/documentation/tutorials/basic/playbin-usage.html
- **Video playback + embedding** (same method shape as audio, plus
  `videoBuildView`) — `linux/video_channel.cc`, same `playbin` element with
  its video sink set to GStreamer's documented GTK embedding element,
  `gtksink` (https://gstreamer.freedesktop.org/documentation/gtk/index.html),
  overlaid on the Flutter `FlView` and kept positioned via an explicit
  `setLayout` call from the Dart-side widget. This is a documented,
  functional tradeoff versus true Flutter compositing (Flutter's Linux/GTK
  embedder has no stable public platform-view API at time of writing) —
  see the "Embedding tradeoff" comment in `linux/video_channel.h`.

### Intentionally still unimplemented — not a gap, a real platform limit

- **Share** (`shareFile`/`shareText`) — there is genuinely no universal
  Linux OS-level share mechanism. `xdg-desktop-portal`'s
  `org.freedesktop.portal.OpenURI` interface only exposes
  `OpenURI`/`OpenFile`/`OpenDirectory` — "open this with a user-chosen
  app" — not a generic content-share broadcast comparable to Android's
  `Intent.ACTION_SEND` or Windows's `DataTransferManager`:
  https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.OpenURI.html
  Desktop-environment-specific mechanisms exist (GNOME "send to" Nautilus
  extensions, KDE's Purpose framework) but none is portal-mediated or
  DE-agnostic, so no native handler is registered for
  `attachment_engine/share` on Linux — `shareFile`/`shareText` keep
  throwing `UnimplementedError` directly from Dart. See
  `linux/share_channel.h` for the full citation.

Still not yet implemented for other reasons (throws `UnimplementedError`):

- **PDF native rendering** and **embedded native webview surfaces** — no
  native-view integration has been wired up for either yet.

You should not need to depend on this package directly — add
[`attachment_engine`](../attachment_engine) to your app instead, and the
right platform implementation is selected automatically.
