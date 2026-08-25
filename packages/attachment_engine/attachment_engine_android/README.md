# attachment_engine_android

[![pub package](https://img.shields.io/pub/v/attachment_engine_android.svg)](https://pub.dev/packages/attachment_engine_android)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The official Android implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for Android applications.

## Native Architecture

* **PDF Rendering**: Native Android `PdfRenderer` and hardware-accelerated drawing.
* **Media Playback**: Android `MediaPlayer` with surface textures and HLS playback.
* **File Operations**: Android `DownloadManager` and `FileProvider` external intent sharing.
* **Type-Safe Dispatch**: Powered by [Pigeon](https://pub.dev/packages/pigeon) `HostApi` communication.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
