// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../config/attachment_engine_config.dart';
import '../models/attachment.dart';
import '../native/native_paths_channel.dart';
import 'cache_metadata_store.dart';
import 'cache_policy.dart';

/// Manages on-disk caching of attachment content, keyed by the stable
/// logical identity of an attachment ([Attachment.stableIdentity]) - never
/// by remote URL, which may be a rotating signed URL.
///
/// Files are stored under the app-private cache directory
/// (`path_provider`'s `getApplicationCacheDirectory` / temp fallback),
/// with filenames derived from a sanitized hash of the logical key, never
/// from raw remote filenames.
class AttachmentCacheManager {
  AttachmentCacheManager({
    required AttachmentMetadataStore metadataStore,
    CachePolicy policy = const CachePolicy(),
    CacheConfig config = const CacheConfig(),
    Future<Directory> Function()? directoryProvider,
  }) : _store = metadataStore,
       _policy = policy,
       _config = config,
       _directoryProvider = directoryProvider ?? _defaultDirectoryProvider;

  final AttachmentMetadataStore _store;
  final CachePolicy _policy;
  final CacheConfig _config;
  final Future<Directory> Function() _directoryProvider;

  Directory? _cacheDir;

  static Future<Directory> _defaultDirectoryProvider() {
    return NativePathsChannel.applicationCacheDirectory();
  }

  /// When [CacheConfig.enabled] is false, this is intentionally a no-op:
  /// no metadata store is initialized and no cache directory is created on
  /// disk.
  Future<void> init() async {
    if (!_config.enabled) return;
    await _store.init();
    _cacheDir = await _directoryProvider();
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  Future<Directory> get _dir async => _cacheDir ??= await _directoryProvider();

  /// Derives a filesystem-safe filename from a logical cache key. Strips
  /// path separators and hashes to avoid depending on unsanitized remote
  /// filenames.
  String sanitizedFileName(String logicalKey, {String? extension}) {
    final hash = sha256.convert(utf8.encode(logicalKey)).toString();
    final safeExt = extension?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '') ?? '';
    return safeExt.isEmpty ? hash : '$hash.$safeExt';
  }

  /// Looks up a valid (non-expired) cache entry for [attachment], returning
  /// its local path if present on disk, or null if absent/invalid.
  ///
  /// Always returns null when [CacheConfig.enabled] is false: with caching
  /// disabled there is no metadata store to consult, so every resolution
  /// must be treated as a miss.
  Future<String?> lookup(Attachment attachment) async {
    if (!_config.enabled) return null;
    final entry = await _store.get(attachment.stableIdentity);
    if (entry == null) return null;
    if (entry.isExpired || _isPastRetention(entry)) return null;
    final file = File(entry.localPath);
    if (!await file.exists()) return null;
    await _store.put(entry.copyWith(lastAccessedAt: DateTime.now()));
    return entry.localPath;
  }

  bool _isPastRetention(CacheEntry entry) {
    final retention = _config.retention;
    if (retention == null) return false;
    return DateTime.now().difference(entry.createdAt) > retention;
  }

  /// Writes [bytes] for a caller that needs a local, on-disk path to render
  /// (e.g. in-memory [BytesAttachmentSource] attachments, or a freshly
  /// downloaded remote attachment), running LRU eviction first if needed to
  /// stay under the size cap.
  ///
  /// When [CacheConfig.enabled] is false, or [bytes] exceeds
  /// [CacheConfig.maxFileSizeBytes], no cache directory is used, no
  /// metadata is persisted and no eviction runs: the bytes are written to a
  /// throwaway file outside the managed cache purely so the resolver has a
  /// local path to hand to a renderer, and that file will never be found
  /// again by [lookup] (there is nothing to look up), so every subsequent
  /// resolution of the same attachment re-fetches/re-materializes it.
  Future<String> write(
    Attachment attachment,
    Uint8List bytes, {
    DateTime? expiresAt,
    CacheEntryCategory category = CacheEntryCategory.original,
  }) async {
    final tooLargeToCache =
        _config.maxFileSizeBytes != null &&
        bytes.length > _config.maxFileSizeBytes!;
    final categoryDisabled =
        (category == CacheEntryCategory.thumbnail &&
            !_config.thumbnailCachingEnabled) ||
        (category == CacheEntryCategory.preview &&
            !_config.previewCachingEnabled);

    if (!_config.enabled || tooLargeToCache || categoryDisabled) {
      return _writeUnmanaged(attachment, bytes);
    }

    await _evictIfNeeded(incomingBytes: bytes.length);

    final dir = await _dir;
    final fileName = sanitizedFileName(
      attachment.stableIdentity,
      extension: attachment.extension,
    );
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final now = DateTime.now();
    await _store.put(
      CacheEntry(
        key: attachment.stableIdentity,
        localPath: file.path,
        sizeBytes: bytes.length,
        createdAt: now,
        lastAccessedAt: now,
        expiresAt: expiresAt ?? attachment.expiresAt,
        attachmentType: attachment.attachmentType.name,
        category: category,
        checksum: sha256.convert(bytes).toString(),
      ),
    );
    return file.path;
  }

  /// Writes [bytes] to a plain temp file, bypassing the managed cache
  /// directory and metadata store entirely.
  Future<String> _writeUnmanaged(Attachment attachment, Uint8List bytes) async {
    final fileName = sanitizedFileName(
      attachment.stableIdentity,
      extension: attachment.extension,
    );
    final file = File('${Directory.systemTemp.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _evictIfNeeded({int incomingBytes = 0}) async {
    final entries = await _store.getAll();
    final toEvict = _policy.selectEntriesToEvict(
      entries,
      incomingBytes: incomingBytes,
    );
    for (final entry in toEvict) {
      await _deleteEntry(entry);
    }
  }

  Future<void> _deleteEntry(CacheEntry entry) async {
    final file = File(entry.localPath);
    if (await file.exists()) {
      await file.delete();
    }
    await _store.delete(entry.key);
  }

  Future<void> clearExpired() async {
    if (!_config.enabled) return;
    final entries = await _store.getAll();
    for (final entry in _policy.selectExpired(entries)) {
      await _deleteEntry(entry);
    }
  }

  Future<void> clearAttachment(Attachment attachment) async {
    if (!_config.enabled) return;
    final entry = await _store.get(attachment.stableIdentity);
    if (entry != null) await _deleteEntry(entry);
  }

  /// Clears cache entries that have not been accessed within [unusedFor]
  /// (default 30 days).
  Future<void> clearUnused({
    Duration unusedFor = const Duration(days: 30),
  }) async {
    if (!_config.enabled) return;
    final cutoff = DateTime.now().subtract(unusedFor);
    final entries = await _store.getAll();
    for (final entry in entries.where(
      (e) => e.lastAccessedAt.isBefore(cutoff),
    )) {
      await _deleteEntry(entry);
    }
  }

  Future<void> clearAll() async {
    if (!_config.enabled) return;
    final entries = await _store.getAll();
    for (final entry in entries) {
      await _deleteEntry(entry);
    }
  }

  Future<int> totalSizeBytes() async {
    if (!_config.enabled) return 0;
    final entries = await _store.getAll();
    return entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
  }
}
