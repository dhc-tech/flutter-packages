# attachment_engine_macos

[![pub package](https://img.shields.io/pub/v/attachment_engine_macos.svg)](https://pub.dev/packages/attachment_engine_macos)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The official macOS implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for macOS applications.

## Native Architecture

* **PDF Rendering**: Native `PDFKit` framework.
* **Media Playback**: `AVFoundation` / `AVKit` playback pipeline.
* **Office & Document Preview**: Native `QuickLook` preview support.
* **Sharing**: `NSSharingService` native desktop sharing.
* **Zero Dependencies**: Pure Swift integration with zero third-party dependencies.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
