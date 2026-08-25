// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/foundation.dart';

import '../download/download_manager.dart';

/// Replaces `dio`: downloads over a hand-written native transport
/// (`URLSessionDownloadTask` on iOS, `HttpURLConnection` on Android) owned
/// by the platform implementation package, streaming progress/completion/
/// error events back through [AttachmentEnginePlatform], while still
/// satisfying the existing [DownloadClient] interface so
/// [DownloadManager]'s retry/queue logic is unchanged.
class NativeDownloadClient implements DownloadClient {
  NativeDownloadClient({String? tempDirPath})
    : _tempDirPath = tempDirPath ?? Directory.systemTemp.path {
    _eventSub = AttachmentEnginePlatform.instance.downloadEvents().listen(
      _onEvent,
      onError: (_) {},
    );
  }

  final String _tempDirPath;
  StreamSubscription<Object?>? _eventSub;

  final Map<String, StreamController<DownloadProgress>> _progressControllers =
      {};
  final Map<String, Completer<Uint8List>> _completers = {};
  final Map<String, String> _destPathByDownloadId = {};

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final downloadId = event['downloadId'] as String?;
    if (downloadId == null) return;
    final type = event['type'] as String?;
    switch (type) {
      case 'progress':
        final received = (event['received'] as num?)?.toInt() ?? 0;
        final totalRaw = (event['total'] as num?)?.toInt();
        _progressControllers[downloadId]?.add(
          DownloadProgress(
            received: received,
            total: (totalRaw == null || totalRaw < 0) ? null : totalRaw,
          ),
        );
      case 'completed':
        final path =
            event['path'] as String? ?? _destPathByDownloadId[downloadId];
        final completer = _completers.remove(downloadId);
        if (completer != null && !completer.isCompleted) {
          if (path == null) {
            completer.completeError(
              StateError('Download completed with no path'),
            );
          } else {
            completer.complete(File(path).readAsBytesSync());
          }
        }
      case 'error':
        final completer = _completers.remove(downloadId);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            Exception(event['message'] as String? ?? 'Download failed'),
          );
        }
    }
  }

  /// Derives a stable, filesystem-safe destination path for [destinationHint]
  /// so retries with `resume: true` reuse the same partial file. Falls back
  /// to a fresh timestamped path when no hint is given (no resume possible).
  @visibleForTesting
  String destPathForTesting(String? destinationHint) =>
      _destPathFor(destinationHint);

  String _destPathFor(String? destinationHint) {
    if (destinationHint == null || destinationHint.isEmpty) {
      return '$_tempDirPath/attachment_engine_dl_${DateTime.now().microsecondsSinceEpoch}';
    }
    // Sanitize: only keep a bounded set of safe characters, never trust the
    // hint (which may originate from a remote URL/filename) directly as a
    // path component.
    final sanitized = destinationHint
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')
        .replaceAll('..', '_');
    final bounded = sanitized.length > 120
        ? sanitized.substring(0, 120)
        : sanitized;
    return '$_tempDirPath/attachment_engine_dl_$bounded';
  }

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) async {
    final destPath = _destPathFor(destinationHint);
    final platform = AttachmentEnginePlatform.instance;
    final downloadId = resume
        ? await platform.resumeDownload(url, const <String, String>{}, destPath)
        : await platform.startDownload(url, const <String, String>{}, destPath);
    _destPathByDownloadId[downloadId] = destPath;
    if (cancelToken is _NativeCancelToken) {
      cancelToken._downloadId = downloadId;
    }

    final completer = Completer<Uint8List>();
    _completers[downloadId] = completer;
    if (onProgress != null) {
      _progressControllers[downloadId] =
          StreamController<DownloadProgress>.broadcast()
            ..stream.listen(onProgress);
    }
    try {
      return await completer.future;
    } finally {
      await _progressControllers.remove(downloadId)?.close();
      _destPathByDownloadId.remove(downloadId);
    }
  }

  @override
  Object createCancelToken() => _NativeCancelToken();

  @override
  void cancel(Object cancelToken) {
    if (cancelToken is _NativeCancelToken && cancelToken._downloadId != null) {
      AttachmentEnginePlatform.instance.cancelDownload(
        cancelToken._downloadId!,
      );
    }
  }

  void dispose() {
    _eventSub?.cancel();
    for (final c in _progressControllers.values) {
      c.close();
    }
    _progressControllers.clear();
  }
}

class _NativeCancelToken {
  String? _downloadId;
}
