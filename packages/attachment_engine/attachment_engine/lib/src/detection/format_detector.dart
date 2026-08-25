// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import '../models/attachment_type.dart';
import 'magic_bytes.dart';
import 'mime_table.dart';

/// Set of extensions considered "office" documents (word processing,
/// spreadsheet, presentation) as opposed to plain PDFs/text/archives.
const _officeExtensions = {
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'odt',
  'ods',
  'odp',
  'rtf',
};

const _textExtensions = {
  'txt',
  'md',
  'csv',
  'json',
  'log',
  'xml',
  'yaml',
  'yml',
};
const _htmlExtensions = {'html', 'htm'};
const _archiveExtensions = {'zip', 'rar', '7z', 'tar', 'gz'};

/// Detects an [AttachmentType] using, in priority order:
/// 1. an explicit mime type (if supplied by the caller / server metadata)
/// 2. magic bytes sniffed from file content
/// 3. the file extension
/// 4. the extension parsed out of a URL
/// 5. an HTTP `content-type` response header
///
/// The first signal that yields a confident answer wins; later signals are
/// only consulted when an earlier one is absent or inconclusive.
class FormatDetector {
  const FormatDetector();

  AttachmentType detect({
    String? explicitMimeType,
    Uint8List? bytes,
    String? extension,
    String? url,
    String? httpContentType,
  }) {
    if (explicitMimeType != null) {
      final fromMime = _typeFromMime(explicitMimeType);
      if (fromMime != null) return fromMime;
    }

    if (bytes != null && bytes.isNotEmpty) {
      final fromMagic = detectTypeFromMagicBytes(bytes);
      if (fromMagic != null) {
        // Disambiguate zip-based container formats (office/scorm) using
        // the extension when we have one, since magic bytes alone can't
        // tell a .docx from a plain .zip.
        if (fromMagic == AttachmentType.archive && extension != null) {
          final byExt = _typeFromExtension(extension);
          if (byExt == AttachmentType.office || byExt == AttachmentType.scorm) {
            return byExt!;
          }
        }
        return fromMagic;
      }
    }

    if (extension != null) {
      final fromExt = _typeFromExtension(extension);
      if (fromExt != null) return fromExt;
    }

    if (url != null) {
      final urlExt = _extensionFromUrl(url);
      if (urlExt != null) {
        final fromExt = _typeFromExtension(urlExt);
        if (fromExt != null) return fromExt;
      }
    }

    if (httpContentType != null) {
      final fromMime = _typeFromMime(httpContentType);
      if (fromMime != null) return fromMime;
    }

    return AttachmentType.unknown;
  }

  String? _extensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final lastDot = path.lastIndexOf('.');
    final lastSlash = path.lastIndexOf('/');
    if (lastDot <= lastSlash || lastDot == -1) return null;
    return path.substring(lastDot + 1).toLowerCase();
  }

  AttachmentType? _typeFromExtension(String rawExtension) {
    final ext = rawExtension.toLowerCase().replaceAll('.', '');
    if (ext == 'scorm') return AttachmentType.scorm;
    if (ext == 'h5p') return AttachmentType.h5p;
    if (_officeExtensions.contains(ext)) return AttachmentType.office;
    if (ext == 'pdf') return AttachmentType.pdf;
    if (_textExtensions.contains(ext)) return AttachmentType.text;
    if (_htmlExtensions.contains(ext)) return AttachmentType.html;
    if (_archiveExtensions.contains(ext)) return AttachmentType.archive;

    final mimeType = lookupMimeTypeForExtension(ext);
    if (mimeType != null) return _typeFromMime(mimeType);
    return null;
  }

  AttachmentType? _typeFromMime(String mimeType) {
    final lower = mimeType.toLowerCase();
    if (lower.startsWith('image/')) return AttachmentType.image;
    if (lower.startsWith('video/')) return AttachmentType.video;
    if (lower.startsWith('audio/')) return AttachmentType.audio;
    if (lower == 'application/pdf') return AttachmentType.pdf;
    if (lower.startsWith('text/html')) return AttachmentType.html;
    if (lower.startsWith('text/')) return AttachmentType.text;
    if (lower == 'application/zip' ||
        lower == 'application/x-zip-compressed' ||
        lower == 'application/x-7z-compressed' ||
        lower == 'application/x-rar-compressed' ||
        lower == 'application/x-tar' ||
        lower == 'application/gzip') {
      return AttachmentType.archive;
    }
    if (lower.contains('msword') ||
        lower.contains('officedocument') ||
        lower.contains('ms-excel') ||
        lower.contains('ms-powerpoint') ||
        lower.contains('opendocument')) {
      return AttachmentType.office;
    }
    return null;
  }
}
