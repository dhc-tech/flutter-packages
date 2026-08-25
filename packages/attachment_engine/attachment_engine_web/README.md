# attachment_engine_web

[![pub package](https://img.shields.io/pub/v/attachment_engine_web.svg)](https://pub.dev/packages/attachment_engine_web)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)

The official Web implementation of [`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and is pulled in automatically for Flutter Web applications.

## Web Architecture

* **Storage & Caching**: Origin Private File System (OPFS) and IndexedDB caching.
* **Downloads**: Native `fetch()` API + OPFS streaming.
* **Media**: HTML5 `<video>` and `<audio>` direct element integration.
* **Web Share API**: Native mobile browser and desktop Web Share integration.
* **WasmGC Ready**: Built entirely with `dart:js_interop` for full WasmGC and JavaScript runtime compatibility.

## Usage

Add `attachment_engine` to your app's `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

For complete documentation and guides, visit [`attachment_engine`](https://pub.dev/packages/attachment_engine).
