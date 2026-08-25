import 'dart:typed_data';

import '../util/value_equatable.dart';

/// Describes where the bytes of an [Attachment] originate from.
///
/// This is a manually-written sealed hierarchy (no code generation) so the
/// package has zero build_runner dependency for its core models.
sealed class AttachmentSource extends ValueEquatable {
  const AttachmentSource();

  /// A remote HTTP(S) URL, possibly a short-lived signed URL.
  const factory AttachmentSource.url(String url) = UrlAttachmentSource;

  /// A file already present on local disk.
  const factory AttachmentSource.file(String path) = FileAttachmentSource;

  /// Raw in-memory bytes (e.g. picked from a form, generated locally).
  const factory AttachmentSource.bytes(
    Uint8List bytes, {
    String? suggestedName,
  }) = BytesAttachmentSource;

  /// Already resolved to a stable cache entry, identified by cache key.
  const factory AttachmentSource.cache(String cacheKey) = CacheAttachmentSource;

  /// Represents an attachment record owned by a remote server, which may
  /// require an authenticated call to resolve to an actual download URL.
  const factory AttachmentSource.serverAttachment(String attachmentId) =
      ServerAttachmentSource;

  /// A live stream (e.g. chunked network stream) rather than a discrete file.
  const factory AttachmentSource.stream(String streamId) =
      StreamAttachmentSource;
}

class UrlAttachmentSource extends AttachmentSource {
  const UrlAttachmentSource(this.url);
  final String url;

  @override
  List<Object?> get props => [url];
}

class FileAttachmentSource extends AttachmentSource {
  const FileAttachmentSource(this.path);
  final String path;

  @override
  List<Object?> get props => [path];
}

class BytesAttachmentSource extends AttachmentSource {
  const BytesAttachmentSource(this.bytes, {this.suggestedName});
  final Uint8List bytes;
  final String? suggestedName;

  @override
  List<Object?> get props => [bytes, suggestedName];
}

class CacheAttachmentSource extends AttachmentSource {
  const CacheAttachmentSource(this.cacheKey);
  final String cacheKey;

  @override
  List<Object?> get props => [cacheKey];
}

class ServerAttachmentSource extends AttachmentSource {
  const ServerAttachmentSource(this.attachmentId);
  final String attachmentId;

  @override
  List<Object?> get props => [attachmentId];
}

class StreamAttachmentSource extends AttachmentSource {
  const StreamAttachmentSource(this.streamId);
  final String streamId;

  @override
  List<Object?> get props => [streamId];
}
