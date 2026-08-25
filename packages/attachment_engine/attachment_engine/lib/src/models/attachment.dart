import '../util/value_equatable.dart';

import 'attachment_capabilities.dart';
import 'attachment_source.dart';
import 'attachment_status.dart';
import 'attachment_type.dart';

/// Core value type representing any piece of content the engine can
/// resolve, cache, render, download or share.
class Attachment extends ValueEquatable {
  const Attachment({
    required this.id,
    required this.name,
    required this.source,
    this.fileName,
    this.extension,
    this.mimeType,
    this.size,
    this.remoteUrl,
    this.localPath,
    this.cacheKey,
    this.checksum,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.duration,
    this.width,
    this.height,
    this.attachmentType = AttachmentType.unknown,
    this.status = AttachmentStatus.discovered,
    this.capabilities = AttachmentCapabilities.none,
    this.metadata = const {},
  });

  /// Stable logical identifier, unaffected by signed-url rotation.
  final String id;

  /// Human-readable display name.
  final String name;

  final AttachmentSource source;

  /// Original file name, if known (never used directly as a cache
  /// filename for security reasons - see [AttachmentCache]).
  final String? fileName;

  /// File extension without a leading dot, e.g. `pdf`.
  final String? extension;

  final String? mimeType;

  /// Size in bytes, if known.
  final int? size;

  final String? remoteUrl;

  final String? localPath;

  /// Stable key used to derive on-disk cache identity. Falls back to [id]
  /// when absent - never derive identity from [remoteUrl] since signed
  /// URLs rotate.
  final String? cacheKey;

  /// Checksum (e.g. sha256) used to validate cached content integrity.
  final String? checksum;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// When the remote source (e.g. a signed URL) expires, if known.
  final DateTime? expiresAt;

  /// Media duration, for audio/video.
  final Duration? duration;

  /// Pixel dimensions, for image/video.
  final int? width;
  final int? height;

  final AttachmentType attachmentType;
  final AttachmentStatus status;
  final AttachmentCapabilities capabilities;

  /// Free-form extension point for host-app specific data.
  final Map<String, Object?> metadata;

  /// Stable identity used for cache/dedup keys: [cacheKey] if present,
  /// otherwise [id]. Never the remote URL, which may be signed/rotating.
  String get stableIdentity => cacheKey ?? id;

  Attachment copyWith({
    String? id,
    String? name,
    AttachmentSource? source,
    String? fileName,
    String? extension,
    String? mimeType,
    int? size,
    String? remoteUrl,
    String? localPath,
    String? cacheKey,
    String? checksum,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    Duration? duration,
    int? width,
    int? height,
    AttachmentType? attachmentType,
    AttachmentStatus? status,
    AttachmentCapabilities? capabilities,
    Map<String, Object?>? metadata,
  }) {
    return Attachment(
      id: id ?? this.id,
      name: name ?? this.name,
      source: source ?? this.source,
      fileName: fileName ?? this.fileName,
      extension: extension ?? this.extension,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      localPath: localPath ?? this.localPath,
      cacheKey: cacheKey ?? this.cacheKey,
      checksum: checksum ?? this.checksum,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      attachmentType: attachmentType ?? this.attachmentType,
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    source,
    fileName,
    extension,
    mimeType,
    size,
    remoteUrl,
    localPath,
    cacheKey,
    checksum,
    createdAt,
    updatedAt,
    expiresAt,
    duration,
    width,
    height,
    attachmentType,
    status,
    capabilities,
    metadata,
  ];
}
