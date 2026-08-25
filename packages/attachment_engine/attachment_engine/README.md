# attachment_engine

[![pub package](https://img.shields.io/pub/v/attachment_engine.svg)](https://pub.dev/packages/attachment_engine)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE)
[![platform](https://img.shields.io/badge/platform-android%20|%20ios%20|%20macos%20|%20windows%20|%20linux%20|%20web-blue.svg)](https://pub.dev/packages/attachment_engine)

A comprehensive, production-grade federated Flutter engine for handling **every** attachment concern in modern mobile, desktop, and web applications:

* 📄 **Multi-Format Rendering**: Native PDF viewer, HTML5/SCORM player, rich text, images, and Office documents.
* 🎵 **Audio & Video Playback**: Full-screen viewer, inline player, background audio, and HLS streaming support.
* 💾 **Resilient Cache Engine**: LRU eviction cap, SHA-256 key hashing, background download resume, and network deduplication.
* 📱 **6-Platform Native Coverage**: Full native performance on **Android, iOS, macOS, Windows, Linux, and Web**.
* 🎨 **Ready-to-Use UI Widgets**: `AttachmentViewer`, `AttachmentPreview`, `AttachmentTile`, `AttachmentList`, and `AttachmentGrid`.
* 🛡️ **Zero-Crash Resilience**: Zip-slip protection, mime-type sniffing, corrupted file detection, and user-friendly error mapping.

---

## 📱 Platform Support Matrix

| Feature | Android | iOS | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| **PDF Viewing** | ✅ Native PDF Surface | ✅ Native PDFKit | ✅ Native PDFKit | ❌ Unimplemented | ❌ Unimplemented | ❌ Unimplemented |
| **Video Playback** | ✅ MediaPlayer / Surface | ✅ AVPlayer | ✅ AVPlayer | ✅ Media Foundation | ✅ GStreamer | ✅ HTML5 Video |
| **Audio Playback** | ✅ MediaPlayer | ✅ AVAudioPlayer | ✅ AVAudioPlayer | ✅ Media Foundation | ✅ GStreamer | ✅ HTML5 Audio |
| **Office Documents** | ✅ External Open Fallback | ✅ Native QuickLook | ✅ Native QuickLook | ✅ Native Open | ✅ Native Open | ✅ In-Browser |
| **HTML / SCORM / H5P** | ✅ WebView | ✅ WKWebView | ✅ WKWebView | ✅ WebView | ✅ Web Surface | ✅ iframe / DOM |
| **File Download** | ✅ Native / Resumable | ✅ NSURLSession | ✅ NSURLSession | ✅ Background IO | ✅ Background IO | ✅ Fetch + OPFS |
| **System Share** | ✅ Android Sharesheet | ✅ UIActivityViewController | ✅ NSSharingService | ✅ Share Interop | ✅ FreeDesktop | ✅ Web Share API |

---

## 🚀 Quick Start

### 1. Installation

Add `attachment_engine` to your `pubspec.yaml`:

```yaml
dependencies:
  attachment_engine: ^0.0.1-dev.1
```

### 2. Initialize the Engine

Initialize `AttachmentManager` in your app's `main()` entrypoint:

```dart
import 'package:flutter/material.dart';
import 'package:attachment_engine/attachment_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AttachmentManager.initializeDefault();
  runApp(const MyApp());
}
```

### 3. Display an Attachment (Viewer & Preview)

```dart
import 'package:flutter/material.dart';
import 'package:attachment_engine/attachment_engine.dart';

class AttachmentScreen extends StatelessWidget {
  const AttachmentScreen({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(attachment.name)),
      body: Center(
        // Full Interactive Viewer:
        child: AttachmentViewer(attachment: attachment),
      ),
    );
  }
}
```

---

## 🧩 UI Components

`attachment_engine` provides plug-and-play UI widgets that adapt to every attachment type:

### `AttachmentViewer`
Full interactive viewer with zoom, swipe, full-screen playback, and action controls.
```dart
AttachmentViewer(
  attachment: attachment,
)
```

### `AttachmentPreview`
Lightweight thumbnail/card preview without initializing heavy platform controllers.
```dart
SizedBox(
  width: 120,
  height: 120,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: AttachmentPreview(attachment: attachment),
  ),
)
```

### `AttachmentTile` & `AttachmentList`
Ready-made list tiles with progress indicator, capability action buttons, and retry states.
```dart
AttachmentList(
  attachments: attachmentList,
  onTapAttachment: (attachment) => AttachmentManager.instance.open(attachment),
)
```

---

## ⚡ Programmatic Management API

```dart
final manager = AttachmentManager.instance;

// 1. Resolve and open an attachment for viewing
final resolved = await manager.open(attachment);

// 2. Share resolved attachment via OS native share sheet
await manager.share(resolved.attachment);

// 3. Open in an external OS-provided application
await manager.openExternally(resolved.attachment);

// 4. Invalidate / delete local cache
await manager.deleteCache(attachment);
```

---

## ⚙️ Custom Configuration

Customize caching limits, retry backoff, and renderers via `AttachmentEngineConfig`:

```dart
final customConfig = AttachmentEngineConfig(
  cache: const CacheConfig(
    maxTotalSizeBytes: 1024 * 1024 * 500, // 500 MB
    retention: Duration(days: 14),
  ),
  download: const DownloadConfig(
    maxConcurrentDownloads: 4,
    maxRetries: 3,
  ),
);

await AttachmentManager.initializeDefault(config: customConfig);
```

---

## 🔒 Security & Resilience

* **Zip-Slip Safe Extraction**: SCORM and ZIP extractors enforce strict path validation to prevent path traversal attacks.
* **Safe Cache Hashing**: File keys are hashed using SHA-256, protecting against invalid characters and directory injections.
* **Content Validation**: Verifies magic bytes to confirm the actual payload matches the declared file extension before execution.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/dhc-tech/flutter-packages/blob/main/LICENSE) file for details.
