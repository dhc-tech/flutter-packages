# attachment_engine_linux

[![pub package](https://img.shields.io/pub/v/attachment_engine_linux.svg)](https://pub.dev/packages/attachment_engine_linux)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The official Linux implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for Linux desktop applications.

## Status

**Development Preview**:
* **Pure Dart (Verified)**:
  * **Paths**: `path_provider` support for application and cache directories.
  * **Open Externally**: `url_launcher` / FreeDesktop OpenURI integration.
  * **Download**: Resumable multi-stream background downloader via `dart:io`.
* **Native C (Preview)**:
  * **Media Playback**: GStreamer `playbin` and `gtksink` GTK overlay.
* **Platform Limitations & Unimplemented**:
  * **Share**: Linux has no universal desktop environment-agnostic share portal; throws `UnimplementedError`.
  * **PDF & WebView**: Native embedded surfaces are currently unimplemented.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
