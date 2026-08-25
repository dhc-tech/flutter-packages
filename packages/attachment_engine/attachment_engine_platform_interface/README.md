# attachment_engine_platform_interface

[![pub package](https://img.shields.io/pub/v/attachment_engine_platform_interface.svg)](https://pub.dev/packages/attachment_engine_platform_interface)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

A common platform interface for the [`attachment_engine`](https://pub.dev/packages/attachment_engine) plugin.

This package defines the pure-Dart platform interface contract that platform-specific implementation packages (`attachment_engine_android`, `attachment_engine_ios`, `attachment_engine_macos`, `attachment_engine_windows`, `attachment_engine_linux`, `attachment_engine_web`) must implement.

## Usage

To use the attachment engine in your application, depend directly on [`attachment_engine`](https://pub.dev/packages/attachment_engine) instead:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

## Implementing a Platform Package

Platform package authors can extend `AttachmentEnginePlatform` to register a new platform backend:

```dart
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';

class AttachmentEngineMyPlatform extends AttachmentEnginePlatform {
  static void registerWith() {
    AttachmentEnginePlatform.instance = AttachmentEngineMyPlatform();
  }
  
  // Implement interface methods...
}
```

For more details, see the main [attachment_engine repository](https://github.com/dhc-tech/flutter-packages).
