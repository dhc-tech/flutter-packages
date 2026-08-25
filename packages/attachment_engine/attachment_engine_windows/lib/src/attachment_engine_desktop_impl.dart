// Copyright 2026 DHC
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:url_launcher/url_launcher.dart';

/// Shared desktop (Windows/Linux) implementation of
/// [AttachmentEnginePlatform]. Paths and open-externally are backed by
/// `path_provider` and `url_launcher` — both published by `flutter.dev`
/// (the Flutter team's own verified publisher, see
/// https://pub.dev/publishers/flutter.dev/packages), not third-party
/// community plugins. Download is `dart:io`'s built-in `HttpClient`.
///
/// Share and audio/video playback now diverge per platform (Windows has a
/// native share implementation via `IDataTransferManagerInterop`; Linux
/// genuinely has no OS-level share mechanism — see the platform-specific
/// `attachment_engine_windows.dart`/`attachment_engine_linux.dart` for
/// details), so those methods are declared directly on
/// `AttachmentEngineWindows`/`AttachmentEngineLinux` rather than in this
/// shared base. This class only covers the capabilities that stay
/// identical, pure-Dart, cross-platform code.
///
/// Still does NOT implement (throws [UnimplementedError]) on either
/// platform: PDF native rendering, and embedded native webview surfaces.
abstract class AttachmentEngineDesktopImpl extends AttachmentEnginePlatform {
  final HttpClient _httpClient = HttpClient();
  final StreamController<Map<Object?, Object?>> _downloadEvents =
      StreamController<Map<Object?, Object?>>.broadcast();
  final Map<String, bool> _cancelled = <String, bool>{};
  int _downloadCounter = 0;

  // ---------------------------------------------------------------------
  // Open externally
  // ---------------------------------------------------------------------

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    try {
      final launched = await launchUrl(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      );
      return NativeOpenResult(
        success: launched,
        message: launched
            ? null
            : 'No application registered for this file type.',
      );
    } catch (e) {
      return NativeOpenResult(success: false, message: e.toString());
    }
  }

  /// Desktop platforms have no in-app Office document viewer wired up here
  /// (no QuickLook equivalent), so this falls back to [openExternally] —
  /// the same documented fallback Android uses.
  @override
  Future<void> openOfficePreview(String path) async {
    await openExternally(path);
  }

  // ---------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------

  @override
  Future<String> getApplicationSupportDirectory() async {
    final dir = await path_provider.getApplicationSupportDirectory();
    return dir.path;
  }

  @override
  Future<String> getApplicationCacheDirectory() async {
    final dir = await path_provider.getApplicationCacheDirectory();
    return dir.path;
  }

  // ---------------------------------------------------------------------
  // Download (dart:io HttpClient — no third-party HTTP package)
  // ---------------------------------------------------------------------

  @override
  Future<String> startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) => _download(url, headers, destPath, resume: false);

  @override
  Future<String> resumeDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) => _download(url, headers, destPath, resume: true);

  Future<String> _download(
    String url,
    Map<String, String> headers,
    String destPath, {
    required bool resume,
  }) async {
    final id = 'attachment_engine_download_${_downloadCounter++}';
    _cancelled[id] = false;

    unawaited(_runDownload(id, url, headers, destPath, resume: resume));

    return id;
  }

  Future<void> _runDownload(
    String id,
    String url,
    Map<String, String> headers,
    String destPath, {
    required bool resume,
  }) async {
    IOSink? sink;
    try {
      final file = File(destPath);
      var receivedSoFar = 0;
      var mode = FileMode.write;
      if (resume && await file.exists()) {
        receivedSoFar = await file.length();
        if (receivedSoFar > 0) {
          mode = FileMode.append;
        }
      }

      final request = await _httpClient.getUrl(Uri.parse(url));
      headers.forEach(request.headers.set);
      if (receivedSoFar > 0) {
        request.headers.set('Range', 'bytes=$receivedSoFar-');
      }

      final response = await request.close();
      if (response.statusCode >= 400) {
        _downloadEvents.add({
          'downloadId': id,
          'type': 'error',
          'path': destPath,
          'message': 'HTTP ${response.statusCode}',
        });
        return;
      }
      // A server that ignores Range restarts from byte 0.
      if (receivedSoFar > 0 && response.statusCode != 206) {
        receivedSoFar = 0;
        mode = FileMode.write;
      }

      final total = response.contentLength >= 0
          ? receivedSoFar + response.contentLength
          : -1;

      sink = file.openWrite(mode: mode);
      var received = receivedSoFar;
      await for (final chunk in response) {
        if (_cancelled[id] ?? false) {
          _downloadEvents.add({
            'downloadId': id,
            'type': 'cancelled',
            'path': destPath,
          });
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        _downloadEvents.add({
          'downloadId': id,
          'type': 'progress',
          'received': received,
          'total': total,
          'path': destPath,
        });
      }
      await sink.flush();
      _downloadEvents.add({
        'downloadId': id,
        'type': 'complete',
        'path': destPath,
      });
    } catch (e) {
      _downloadEvents.add({
        'downloadId': id,
        'type': 'error',
        'path': destPath,
        'message': e.toString(),
      });
    } finally {
      await sink?.close();
      _cancelled.remove(id);
    }
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    _cancelled[downloadId] = true;
  }

  @override
  Stream<Map<Object?, Object?>> downloadEvents() => _downloadEvents.stream;
}
