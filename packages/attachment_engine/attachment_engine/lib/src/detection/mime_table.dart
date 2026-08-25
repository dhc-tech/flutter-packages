/// Hand-written extension -> MIME type lookup table, replacing the
/// third-party `mime` package. Covers the formats referenced by
/// [FormatDetector] / the capability spec. Not exhaustive, but sufficient
/// for attachment-type classification purposes.
const Map<String, String> kExtensionToMimeType = {
  // Images
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'bmp': 'image/bmp',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'heic': 'image/heic',
  'heif': 'image/heif',

  // Video
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
  'avi': 'video/x-msvideo',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  '3gp': 'video/3gpp',

  // Audio
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',

  // Documents
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'rtf': 'application/rtf',

  // Text
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'log': 'text/plain',
  'xml': 'application/xml',
  'yaml': 'application/x-yaml',
  'yml': 'application/x-yaml',

  // Web
  'html': 'text/html',
  'htm': 'text/html',

  // Archives
  'zip': 'application/zip',
  'rar': 'application/x-rar-compressed',
  '7z': 'application/x-7z-compressed',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
  'scorm': 'application/zip',
  'h5p': 'application/zip',
};

/// Looks up the MIME type for a file name/extension. Mirrors
/// `mime`'s `lookupMimeType('file.$ext')` for the subset of formats this
/// plugin cares about.
String? lookupMimeTypeForExtension(String extensionOrFileName) {
  final ext = extensionOrFileName.contains('.')
      ? extensionOrFileName.split('.').last.toLowerCase()
      : extensionOrFileName.toLowerCase();
  return kExtensionToMimeType[ext];
}
