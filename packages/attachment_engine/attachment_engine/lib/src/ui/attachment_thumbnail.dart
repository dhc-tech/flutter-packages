// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';

/// Small square thumbnail for an attachment, used inside [AttachmentTile]
/// and [AttachmentGrid]. Falls back to a type icon when no local image is
/// available.
class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({
    super.key,
    required this.attachment,
    this.size = 48,
  });

  final Attachment attachment;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (attachment.attachmentType == .image && attachment.localPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(attachment.localPath!),
          width: size,
          height: size,
          fit: .cover,
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Icon(_iconFor(attachment.attachmentType), size: size * 0.6),
    );
  }

  IconData _iconFor(AttachmentType type) {
    switch (type) {
      case .image:
        return Icons.image;
      case .pdf:
        return Icons.picture_as_pdf;
      case .document:
      case .office:
        return Icons.description;
      case .text:
        return Icons.article;
      case .csv:
        return Icons.table_chart;
      case .html:
        return Icons.public;
      case .scorm:
      case .h5p:
        return Icons.school;
      case .video:
        return Icons.movie;
      case .audio:
        return Icons.audiotrack;
      case .archive:
        return Icons.folder_zip;
      case .unknown:
        return Icons.insert_drive_file;
    }
  }
}
