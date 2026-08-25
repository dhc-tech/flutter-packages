# attachment_engine_windows

[![pub package](https://img.shields.io/pub/v/attachment_engine_windows.svg)](https://pub.dev/packages/attachment_engine_windows)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The official Windows implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for Windows desktop applications.

## Architecture

* **File Operations**: Native Win32 path resolution and external application launchers.
* **Download Engine**: High-throughput resumable downloads via `dart:io`.
* **Sharing**: Native `IDataTransferManagerInterop` share integrations.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
