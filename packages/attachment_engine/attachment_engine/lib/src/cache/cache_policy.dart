// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'cache_metadata_store.dart';

/// Retention rules for the attachment cache: a maximum total size with
/// least-recently-used eviction, plus explicit clear operations.
class CachePolicy {
  const CachePolicy({this.maxTotalSizeBytes = 500 * 1024 * 1024});

  /// Maximum total bytes the cache may occupy before LRU eviction runs.
  final int maxTotalSizeBytes;

  /// Given all current [entries], returns the subset that should be
  /// evicted (oldest-accessed first) to bring total size at or under
  /// [maxTotalSizeBytes], optionally after also making room for
  /// [incomingBytes] of new content.
  ///
  /// [CacheEntry.pinned] entries are never selected — a file the host app
  /// marked "keep available offline" survives cache pressure. Their bytes
  /// still count toward the current total, so if enough content is
  /// pinned, the cache can end up genuinely over [maxTotalSizeBytes] with
  /// nothing left evictable; that's the deliberate tradeoff of pinning,
  /// not a bug.
  List<CacheEntry> selectEntriesToEvict(
    List<CacheEntry> entries, {
    int incomingBytes = 0,
  }) {
    final sorted = [...entries]
      ..sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));
    var total =
        entries.fold<int>(0, (sum, e) => sum + e.sizeBytes) + incomingBytes;
    final toEvict = <CacheEntry>[];
    for (final entry in sorted) {
      if (total <= maxTotalSizeBytes) break;
      if (entry.pinned) continue;
      toEvict.add(entry);
      total -= entry.sizeBytes;
    }
    return toEvict;
  }

  /// Entries whose [CacheEntry.expiresAt] has passed — excluding
  /// [CacheEntry.pinned] ones, for the same "automatic cleanup never
  /// removes a pinned file" reason as [selectEntriesToEvict].
  List<CacheEntry> selectExpired(List<CacheEntry> entries) {
    return entries.where((e) => e.isExpired && !e.pinned).toList();
  }
}
