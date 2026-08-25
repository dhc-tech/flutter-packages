import 'dart:io';

import 'package:flutter/material.dart';

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
    if (attachment.attachmentType == AttachmentType.image &&
        attachment.localPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(attachment.localPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
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
      case AttachmentType.image:
        return Icons.image;
      case AttachmentType.pdf:
        return Icons.picture_as_pdf;
      case AttachmentType.document:
      case AttachmentType.office:
        return Icons.description;
      case AttachmentType.text:
        return Icons.article;
      case AttachmentType.html:
        return Icons.public;
      case AttachmentType.scorm:
      case AttachmentType.h5p:
        return Icons.school;
      case AttachmentType.video:
        return Icons.movie;
      case AttachmentType.audio:
        return Icons.audiotrack;
      case AttachmentType.archive:
        return Icons.folder_zip;
      case AttachmentType.unknown:
        return Icons.insert_drive_file;
    }
  }
}
