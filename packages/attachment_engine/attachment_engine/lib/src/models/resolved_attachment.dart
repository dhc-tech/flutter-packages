import '../util/value_equatable.dart';

import 'attachment.dart';
import 'attachment_capabilities.dart';

/// Result of `AttachmentResolver.resolve`: a local, usable file plus the
/// (possibly updated) attachment metadata and its computed capabilities.
class ResolvedAttachment extends ValueEquatable {
  const ResolvedAttachment({
    required this.attachment,
    required this.localPath,
    required this.capabilities,
    this.fromCache = false,
  });

  final Attachment attachment;
  final String localPath;
  final AttachmentCapabilities capabilities;

  /// True if this result was served from cache rather than freshly
  /// downloaded/read.
  final bool fromCache;

  @override
  List<Object?> get props => [attachment, localPath, capabilities, fromCache];
}
