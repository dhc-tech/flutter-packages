import 'dart:io';

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'attachment_thumbnail.dart';

/// Lightweight, non-interactive preview of an attachment. Deliberately
/// never instantiates a full renderer/controller (no video/audio/pdf
/// controllers) - it is meant for list/card contexts where many previews
/// may be on-screen at once.
class AttachmentPreview extends StatelessWidget {
  const AttachmentPreview({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    switch (attachment.attachmentType) {
      case AttachmentType.image:
        if (attachment.localPath != null) {
          return Image.file(File(attachment.localPath!), fit: BoxFit.cover);
        }
        if (attachment.remoteUrl != null) {
          return Image.network(attachment.remoteUrl!, fit: BoxFit.cover);
        }
        return AttachmentThumbnail(attachment: attachment);
      case AttachmentType.text:
        return _TextSnippet(attachment: attachment);
      default:
        return AttachmentThumbnail(attachment: attachment, size: 64);
    }
  }
}

class _TextSnippet extends StatelessWidget {
  const _TextSnippet({required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final path = attachment.localPath;
    if (path == null) return const Text('');
    return FutureBuilder<String>(
      future: File(path).readAsString().catchError((_) => ''),
      builder: (context, snapshot) {
        final text = snapshot.data ?? '';
        final snippet = text.length > 200 ? '${text.substring(0, 200)}…' : text;
        return Text(snippet, maxLines: 3, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
