// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Lifecycle status of an [Attachment] as it moves through discovery,
/// resolution, caching, rendering and cleanup.
enum AttachmentStatus {
  /// Known to exist (e.g. returned from an API) but nothing else done yet.
  discovered,

  /// Being validated / format-detected.
  validating,

  /// Resolution in progress (checking local/cache/network).
  resolving,

  /// A download or fetch is actively in progress.
  downloading,

  /// Present in the local cache and considered valid.
  cached,

  /// Fully resolved to a local, usable file.
  ready,

  /// Actively being rendered / played / viewed.
  rendering,

  /// A recoverable or terminal failure occurred. See [AttachmentFailure].
  failed,

  /// The remote source or cached copy has expired and needs refresh.
  expired,

  /// Local cache entry has been removed.
  cleaned,
}
