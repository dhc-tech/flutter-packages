// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

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
import '../models/attachment_type.dart';
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

  /// Releases resources held by this resolver's collaborators:
  /// [DownloadManager.dispose] (per-key progress controllers), and, if the
  /// download client is a [NativeDownloadClient] (holds a platform-channel
  /// event subscription), that too. Call this before discarding a resolver
  /// instance — e.g. [AttachmentManager.dispose] does, and
  /// [AttachmentManager.initializeDefault] does when replacing an existing
  /// singleton.
  void dispose() {
    _downloadManager.dispose();
    if (_downloadManager.client case final NativeDownloadClient native) {
      native.dispose();
    }
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
      // Pass the bytes through so _finish's attachmentType auto-detection
      // can use magic-byte sniffing too, same as the downloaded-bytes
      // path below — not just extension/mime/url.
      return _finish(attachment, path, fromCache: false, bytes: source.bytes);
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
      return _finish(attachment, path, fromCache: false, bytes: result.bytes);
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
    Uint8List? bytes,
  }) {
    var resolvedAttachment = attachment.copyWith(
      localPath: localPath,
      status: AttachmentStatus.ready,
    );
    // Populate attachmentType when the caller left it unset: without this,
    // an Attachment built with only id/name/source (the documented,
    // minimal-required-fields usage) would resolve successfully but stay
    // permanently `unknown`, so RendererRegistry would always fall through
    // to UnknownAttachmentRenderer instead of picking a real renderer.
    if (resolvedAttachment.attachmentType == AttachmentType.unknown) {
      final source = resolvedAttachment.source;
      final detected = _formatDetector.detect(
        explicitMimeType: resolvedAttachment.mimeType,
        bytes: bytes,
        extension: resolvedAttachment.extension,
        url:
            resolvedAttachment.remoteUrl ??
            (source is UrlAttachmentSource ? source.url : null),
      );
      if (detected != AttachmentType.unknown) {
        resolvedAttachment = resolvedAttachment.copyWith(
          attachmentType: detected,
        );
      }
    }
    final capabilities = _capabilityEngine.derive(resolvedAttachment);
    return ResolvedAttachment(
      attachment: resolvedAttachment.copyWith(capabilities: capabilities),
      localPath: localPath,
      capabilities: capabilities,
      fromCache: fromCache,
    );
  }
}
