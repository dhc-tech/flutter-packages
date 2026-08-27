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

/// Thrown when [DownloadManager.cancel] is called for a download that was
/// still queued (waiting for a concurrency slot) rather than actually
/// in flight — cancelling a queued download has no [DownloadClient]
/// cancel token to forward to, so it's handled entirely inside
/// [DownloadManager] by never letting the queued request acquire a slot.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
  @override
  String toString() =>
      'DownloadCancelledException: download was cancelled '
      'while still queued for a concurrency slot.';
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

  /// The underlying [DownloadClient]. Exposed so a caller that knows it
  /// constructed (or was handed) a resource-owning implementation — e.g.
  /// `NativeDownloadClient`, which holds a platform-channel event
  /// subscription — can dispose it too. [DownloadManager] itself stays
  /// agnostic of any particular [DownloadClient] implementation.
  DownloadClient get client => _client;

  final int maxRetries;
  final DownloadConfig _config;
  final int _maxConcurrent;

  final Map<String, Object> _cancelTokens = {};
  final Map<String, StreamController<DownloadProgress>> _progressControllers =
      {};

  int _running = 0;
  final List<Completer<void>> _waiters = [];

  /// Tracks a still-queued (not yet running) download's waiter, keyed by
  /// its download `key`, so [cancel] can reach it — [_waiters] alone has
  /// no way to look a specific caller's request back up by key.
  final Map<String, Completer<void>> _waitersByKey = {};

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

  Future<void> _acquireSlot(String key) async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _waitersByKey[key] = completer;
    _waiters.add(completer);
    try {
      await completer.future;
    } finally {
      _waitersByKey.remove(key);
    }
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
    await _acquireSlot(key);
    try {
      return await _downloadOnce(key, url, attempt: attempt);
    } finally {
      _releaseSlot();
      // This call's full attempt sequence (including any retries — see
      // _downloadOnce's recursion) is done: close and drop this key's
      // progress controller rather than leaving it in _progressControllers
      // forever. A later download() for the same key just lazily creates
      // a fresh one via progressStream()'s `??=`.
      unawaited(_progressControllers.remove(key)?.close());
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
      // A deliberate cancellation is not a transient failure to retry —
      // retrying it would defeat the entire point of cancel(), silently
      // turning "the user cancelled this download" back into "keep
      // downloading it anyway" as long as attempts remain.
      if (e is! DownloadCancelledException && attempt < maxRetries) {
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
      return;
    }
    // Not yet running — still queued behind maxConcurrentDownloads other
    // in-flight downloads, so there's no DownloadClient cancel token to
    // forward to. Cancel the wait itself instead: remove it from the
    // waiter queue and reject its completer, so it never gets a slot
    // (and never silently starts downloading anyway once one frees up).
    final waiter = _waitersByKey.remove(key);
    if (waiter != null) {
      _waiters.remove(waiter);
      if (!waiter.isCompleted) {
        waiter.completeError(const DownloadCancelledException());
      }
    }
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
