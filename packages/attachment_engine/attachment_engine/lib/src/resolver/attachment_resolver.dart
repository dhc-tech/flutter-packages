import 'dart:io';
import 'dart:typed_data';

import '../cache/attachment_cache_manager.dart';
import '../capability/capability_engine.dart';
import '../concurrency/in_flight_registry.dart';
import '../config/attachment_engine_config.dart';
import '../detection/format_detector.dart';
import '../download/download_manager.dart';
import '../native/native_download_channel.dart';
import '../models/attachment.dart';
import '../models/attachment_failure.dart';
import '../models/attachment_source.dart';
import '../models/attachment_status.dart';
import '../models/resolved_attachment.dart';

/// Hook for checking network reachability. Default implementation performs
/// a lightweight DNS lookup, swallowing any error into `false`.
abstract class ConnectivityChecker {
  Future<bool> hasConnection();
}

class DefaultConnectivityChecker implements ConnectivityChecker {
  const DefaultConnectivityChecker();

  @override
  Future<bool> hasConnection() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Result type used internally to thread failures without throwing across
/// resolution stages.
class AttachmentResolutionException implements Exception {
  AttachmentResolutionException(this.failure);
  final AttachmentFailure failure;
}

/// Orchestrates resolving an [Attachment] to a usable local file:
/// validate -> already local? -> cached? -> network available? ->
/// download -> [ResolvedAttachment].
///
/// Concurrent resolutions for the same logical attachment are deduplicated
/// via [InFlightRegistry].
class AttachmentResolver {
  AttachmentResolver({
    required AttachmentCacheManager cacheManager,
    DownloadManager? downloadManager,
    ConnectivityChecker connectivityChecker =
        const DefaultConnectivityChecker(),
    FormatDetector formatDetector = const FormatDetector(),
    CapabilityEngine capabilityEngine = const CapabilityEngine(),
    DownloadConfig downloadConfig = const DownloadConfig(),
  }) : _cacheManager = cacheManager,
       _downloadManager =
           downloadManager ??
           DownloadManager(
             client: NativeDownloadClient(),
             config: downloadConfig,
           ),
       _connectivityChecker = connectivityChecker,
       _formatDetector = formatDetector,
       _capabilityEngine = capabilityEngine;

  final AttachmentCacheManager _cacheManager;
  final DownloadManager _downloadManager;
  final ConnectivityChecker _connectivityChecker;
  final FormatDetector _formatDetector;
  final CapabilityEngine _capabilityEngine;

  final InFlightRegistry<ResolvedAttachment> _inFlight =
      InFlightRegistry<ResolvedAttachment>();

  Future<ResolvedAttachment> resolve(Attachment attachment) {
    return _inFlight.run(attachment.stableIdentity, () => _resolve(attachment));
  }

  Future<ResolvedAttachment> _resolve(Attachment attachment) async {
    final source = attachment.source;

    // 1. Already a local file.
    if (source is FileAttachmentSource) {
      final file = File(source.path);
      if (!await file.exists()) {
        throw AttachmentResolutionException(const AttachmentNotFound());
      }
      return _finish(attachment, source.path, fromCache: false);
    }

    // 2. In-memory bytes: write straight to cache so we have a stable path.
    if (source is BytesAttachmentSource) {
      final path = await _cacheManager.write(attachment, source.bytes);
      return _finish(attachment, path, fromCache: false);
    }

    // 3. Cache lookup by stable logical identity (never by signed URL).
    final cached = await _cacheManager.lookup(attachment);
    if (cached != null) {
      return _finish(attachment, cached, fromCache: true);
    }

    // 4. Needs network: check connectivity before attempting anything.
    final url =
        attachment.remoteUrl ??
        (source is UrlAttachmentSource ? source.url : null);
    if (url == null) {
      throw AttachmentResolutionException(const InvalidSource());
    }

    final online = await _connectivityChecker.hasConnection();
    if (!online) {
      throw AttachmentResolutionException(const NetworkUnavailable());
    }

    try {
      final result = await _downloadManager.download(
        attachment.stableIdentity,
        url,
      );
      _validateMagicBytes(attachment, result.bytes);
      final path = await _cacheManager.write(
        attachment,
        result.bytes,
        expiresAt: attachment.expiresAt,
      );
      return _finish(attachment, path, fromCache: false);
    } on AttachmentResolutionException {
      rethrow;
    } catch (e) {
      throw AttachmentResolutionException(DownloadFailed(cause: e));
    }
  }

  /// Best-effort validation that downloaded bytes' magic-byte-detected type
  /// is consistent with the attachment's declared type, where feasible.
  void _validateMagicBytes(Attachment attachment, Uint8List bytes) {
    if (bytes.isEmpty) return;
    final detected = _formatDetector.detect(
      bytes: bytes,
      extension: attachment.extension,
    );
    if (attachment.attachmentType.name != 'unknown' &&
        detected.name != 'unknown' &&
        detected != attachment.attachmentType) {
      // Mismatch is not necessarily fatal (magic-byte tables are limited),
      // so we only fail when we're fairly confident: both sides resolved
      // to a concrete, incompatible type.
      throw AttachmentResolutionException(const CorruptedFile());
    }
  }

  ResolvedAttachment _finish(
    Attachment attachment,
    String localPath, {
    required bool fromCache,
  }) {
    final resolvedAttachment = attachment.copyWith(
      localPath: localPath,
      status: AttachmentStatus.ready,
    );
    final capabilities = _capabilityEngine.derive(resolvedAttachment);
    return ResolvedAttachment(
      attachment: resolvedAttachment.copyWith(capabilities: capabilities),
      localPath: localPath,
      capabilities: capabilities,
      fromCache: fromCache,
    );
  }
}
