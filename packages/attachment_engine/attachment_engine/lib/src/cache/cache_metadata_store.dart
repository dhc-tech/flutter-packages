// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../native/native_paths_channel.dart';

/// Category of a cached file, used to allow selective eviction (e.g. clear
/// all thumbnails without touching full originals).
enum CacheEntryCategory { thumbnail, preview, original }

/// Metadata about a single cached attachment file.
class CacheEntry {
  const CacheEntry({
    required this.key,
    required this.localPath,
    required this.sizeBytes,
    required this.createdAt,
    required this.lastAccessedAt,
    this.expiresAt,
    this.attachmentType,
    this.category = CacheEntryCategory.original,
    this.checksum,
  });

  final String key;
  final String localPath;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final DateTime? expiresAt;
  final String? attachmentType;
  final CacheEntryCategory category;
  final String? checksum;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  CacheEntry copyWith({DateTime? lastAccessedAt}) {
    return CacheEntry(
      key: key,
      localPath: localPath,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      expiresAt: expiresAt,
      attachmentType: attachmentType,
      category: category,
      checksum: checksum,
    );
  }

  Map<String, Object?> toMap() => {
    'key': key,
    'localPath': localPath,
    'sizeBytes': sizeBytes,
    'createdAt': createdAt.toIso8601String(),
    'lastAccessedAt': lastAccessedAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'attachmentType': attachmentType,
    'category': category.name,
    'checksum': checksum,
  };

  static CacheEntry fromMap(Map<dynamic, dynamic> map) {
    return CacheEntry(
      key: map['key'] as String,
      localPath: map['localPath'] as String,
      sizeBytes: map['sizeBytes'] as int,
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastAccessedAt: DateTime.parse(map['lastAccessedAt'] as String),
      expiresAt: map['expiresAt'] == null
          ? null
          : DateTime.parse(map['expiresAt'] as String),
      attachmentType: map['attachmentType'] as String?,
      category: CacheEntryCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => CacheEntryCategory.original,
      ),
      checksum: map['checksum'] as String?,
    );
  }
}

/// Abstract persistence interface for cache metadata. A host app that
/// already has its own database set up should implement this against its
/// own storage instead of using [FileBasedMetadataStore].
abstract class AttachmentMetadataStore {
  Future<void> init();
  Future<CacheEntry?> get(String key);
  Future<List<CacheEntry>> getAll();
  Future<void> put(CacheEntry entry);
  Future<void> delete(String key);
  Future<void> clear();
}

/// Backwards-compatible alias used before the Hive removal.
typedef HiveCacheMetadataStore = FileBasedMetadataStore;

/// Pure-Dart, file-based implementation of [AttachmentMetadataStore]:
/// a single JSON index file (`{fileName}.json`) under the app-support
/// directory maps keys to [CacheEntry] maps. There is no native dependency
/// and no third-party package (replaces `hive`/`hive_flutter`).
///
/// Corruption recovery: if the index file exists but fails to parse as
/// JSON (e.g. truncated by a crash mid-write), it is treated as empty
/// rather than throwing, so the cache degrades to "cold" instead of
/// crashing the host app.
class FileBasedMetadataStore implements AttachmentMetadataStore {
  FileBasedMetadataStore({
    this.fileName = 'attachment_engine_cache_metadata.json',
    Future<Directory> Function()? directoryProvider,
    this.flushDebounce = const Duration(seconds: 2),
  }) : _directoryProvider =
           directoryProvider ?? NativePathsChannel.applicationSupportDirectory;

  final String fileName;
  final Future<Directory> Function() _directoryProvider;

  /// How long [put]/[delete] wait, coalescing further calls, before
  /// actually persisting the in-memory index to disk. See [_pendingFlush]
  /// for why. Exposed mainly so tests don't have to wait out a real
  /// multi-second delay to observe a flush.
  final Duration flushDebounce;

  File? _file;
  Map<String, Map<String, Object?>> _index = {};

  /// Coalesces a burst of [put]/[delete] calls in quick succession (e.g.
  /// every tile in a grid/list bumping its `lastAccessedAt` on the same
  /// frame) into a single index rewrite instead of one full-index
  /// `jsonEncode` + disk write per call. `put`/`delete` already keep
  /// `_index` itself immediately up to date in memory — this only defers
  /// *persisting* that to disk.
  ///
  /// This trades a small durability window (a crash within the debounce
  /// delay loses the pending metadata update) for avoiding an O(index
  /// size) disk write on every single cache hit — consistent with this
  /// store's existing corruption-recovery stance: losing/corrupting the
  /// metadata index degrades the cache to cold (safe, if slower), it
  /// never loses the actual cached files or corrupts host app data.
  Timer? _pendingFlush;

  @override
  Future<void> init() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _file = File('${dir.path}/$fileName');
    if (await _file!.exists()) {
      try {
        final content = await _file!.readAsString();
        if (content.trim().isEmpty) {
          _index = {};
        } else {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          _index = decoded.map(
            (k, v) => MapEntry(k, Map<String, Object?>.from(v as Map)),
          );
        }
      } catch (_) {
        // Corrupted index: start fresh rather than crashing.
        _index = {};
      }
    } else {
      _index = {};
    }
  }

  File get _requireFile {
    final file = _file;
    if (file == null) {
      throw StateError(
        'FileBasedMetadataStore.init() must be called before use.',
      );
    }
    return file;
  }

  Future<void> _flush() async {
    await _requireFile.writeAsString(jsonEncode(_index), flush: true);
  }

  void _scheduleFlush() {
    _pendingFlush ??= Timer(flushDebounce, () {
      _pendingFlush = null;
      unawaited(_flush());
    });
  }

  @override
  Future<CacheEntry?> get(String key) async {
    final map = _index[key];
    if (map == null) return null;
    return CacheEntry.fromMap(map);
  }

  @override
  Future<List<CacheEntry>> getAll() async {
    return _index.values.map(CacheEntry.fromMap).toList();
  }

  @override
  Future<void> put(CacheEntry entry) async {
    _index[entry.key] = entry.toMap();
    _scheduleFlush();
  }

  @override
  Future<void> delete(String key) async {
    _index.remove(key);
    _scheduleFlush();
  }

  @override
  Future<void> clear() async {
    _index = {};
    _pendingFlush?.cancel();
    _pendingFlush = null;
    await _flush(); // Immediate — a rare, deliberate wipe, not a hot path.
  }

  /// Flushes a pending debounced write immediately instead of waiting out
  /// its timer. Not required for correctness (the timer fires on its
  /// own), but callers that control the app/isolate lifecycle (e.g. on
  /// pause/shutdown) can call this so a pending metadata update isn't
  /// lost if the process exits before the timer fires.
  Future<void> flushPending() async {
    if (_pendingFlush == null) return;
    _pendingFlush!.cancel();
    _pendingFlush = null;
    await _flush();
  }
}
