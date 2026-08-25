// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import '../config/attachment_engine_config.dart';

/// Progress update for an in-flight download.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});
  final int received;
  final int? total;

  double? get fraction =>
      (total == null || total == 0) ? null : received / total!;
}

/// Minimal HTTP client abstraction the download manager depends on, so
/// tests can inject a fake implementation instead of hitting the network.
/// The default implementation wraps [Dio].
abstract class DownloadClient {
  /// Downloads [url] fully into memory, reporting progress via [onProgress].
  /// [cancelToken] can be used to cancel an in-flight request.
  ///
  /// [destinationHint] is a stable identifier (e.g. derived from the cache
  /// key) that implementations may use to persist partial-download state
  /// across attempts. When [resume] is true, implementations that support
  /// HTTP range / resume-data should attempt to continue a previous partial
  /// download for the same [destinationHint] instead of restarting from
  /// scratch; if the server/OS doesn't support resuming, they must fall back
  /// to a clean full download rather than corrupting output.
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  });

  /// Creates a cancellation token compatible with [download]'s [cancelToken].
  Object createCancelToken();

  /// Cancels a previously-created token.
  void cancel(Object cancelToken);
}

/// States a queued download can be in.
enum DownloadState { queued, running, paused, completed, failed, cancelled }

/// Result of a completed download attempt.
class DownloadResult {
  const DownloadResult({required this.bytes, required this.url});
  final Uint8List bytes;
  final String url;
}

/// Orchestrates downloads with progress reporting, cancellation and retry.
///
/// Retries (including after `cancel`) pass a stable `destinationHint`
/// (derived from [key]) and `resume: true` to the underlying [DownloadClient]
/// starting with the second attempt, so a native client backed by HTTP range
/// requests (Android) or `URLSessionDownloadTask` resume-data (iOS) can
/// continue a partial download instead of restarting from scratch. If the
/// server ignores the range request or the OS resume-data is invalid/expired,
/// the native layer falls back to a full clean restart automatically - this
/// class does not need to know which happened.
class DownloadManager {
  DownloadManager({
    required DownloadClient client,
    int? maxRetries,
    DownloadConfig config = const DownloadConfig(),
  }) : _client = client,
       // `maxRetries` kept as a positional override for backward
       // compatibility with existing call sites/tests; `config.maxRetries`
       // is used when it isn't explicitly overridden.
       maxRetries = maxRetries ?? config.maxRetries,
       _config = config,
       _maxConcurrent = config.maxConcurrentDownloads {
    _validateConcurrency();
  }

  final DownloadClient _client;
  final int maxRetries;
  final DownloadConfig _config;
  final int _maxConcurrent;

  final Map<String, Object> _cancelTokens = {};
  final Map<String, StreamController<DownloadProgress>> _progressControllers =
      {};

  int _running = 0;
  final List<Completer<void>> _waiters = [];

  void _validateConcurrency() {
    if (_maxConcurrent <= 0) {
      throw AttachmentConfigValidationError(
        'maxConcurrentDownloads must be greater than zero (was $_maxConcurrent).',
      );
    }
  }

  Stream<DownloadProgress> progressStream(String key) {
    return (_progressControllers[key] ??=
            StreamController<DownloadProgress>.broadcast())
        .stream;
  }

  Future<void> _acquireSlot() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _running++;
  }

  void _releaseSlot() {
    _running--;
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      if (!next.isCompleted) next.complete();
    }
  }

  Future<DownloadResult> download(
    String key,
    String url, {
    int attempt = 1,
  }) async {
    await _acquireSlot();
    try {
      return await _downloadOnce(key, url, attempt: attempt);
    } finally {
      _releaseSlot();
    }
  }

  Future<DownloadResult> _downloadOnce(
    String key,
    String url, {
    required int attempt,
  }) async {
    final token = _client.createCancelToken();
    _cancelTokens[key] = token;
    try {
      final bytes = await _client
          .download(
            url,
            cancelToken: token,
            destinationHint: key,
            resume: _config.resumeEnabled && attempt > 1,
            onProgress: (progress) {
              _progressControllers[key]?.add(progress);
            },
          )
          .timeout(_config.connectTimeout + _config.receiveTimeout);
      return DownloadResult(bytes: bytes, url: url);
    } catch (e) {
      if (attempt < maxRetries) {
        final delay = _backoffDelay(attempt);
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        _cancelTokens.remove(key);
        return _downloadOnce(key, url, attempt: attempt + 1);
      }
      rethrow;
    } finally {
      _cancelTokens.remove(key);
    }
  }

  Duration _backoffDelay(int attemptJustFailed) {
    switch (_config.retryBackoff) {
      case DownloadRetryBackoff.none:
        return Duration.zero;
      case DownloadRetryBackoff.linear:
        return _config.retryBaseDelay * attemptJustFailed;
      case DownloadRetryBackoff.exponential:
        return _config.retryBaseDelay * (1 << (attemptJustFailed - 1));
    }
  }

  void cancel(String key) {
    final token = _cancelTokens[key];
    if (token != null) {
      _client.cancel(token);
      _cancelTokens.remove(key);
    }
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
