# attachment_engine_windows

[![pub package](https://img.shields.io/pub/v/attachment_engine_windows.svg)](https://pub.dev/packages/attachment_engine_windows)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The Windows implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for Windows desktop applications.

## Status

**Development Preview**:
* **Pure Dart (Verified)**:
  * **Paths**: `path_provider` support for application and cache directories.
  * **Open Externally**: `url_launcher` integration for opening files with default system applications.
  * **Download**: Resumable file downloads via `dart:io` with `Range` header support.
* **Native C++ (Preview)**:
  * **Sharing**: `IDataTransferManagerInterop` COM API integration.
  * **Media Playback**: Media Foundation (`IMFMediaEngine`) audio/video channels.
* **Unimplemented**:
  * Native PDFKit-equivalent rendering and embedded WebView surfaces are currently unimplemented.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
