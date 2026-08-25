# attachment_engine_ios

[![pub package](https://img.shields.io/pub/v/attachment_engine_ios.svg)](https://pub.dev/packages/attachment_engine_ios)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The official iOS implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for iOS applications.

## Native Architecture

* **PDF Rendering**: Apple `PDFKit` with pinch-to-zoom and page caching.
* **Media Playback**: `AVPlayer` and `AVAudioPlayer` for high-performance audio/video rendering.
* **Document Preview**: `QuickLook` (`QLPreviewController`) for native Office document viewing.
* **Sharing**: Native `UIActivityViewController` sharing sheet.
* **Type-Safe Dispatch**: Powered by [Pigeon](https://pub.dev/packages/pigeon) `HostApi` communication.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
