import 'package:flutter/material.dart';

import '../models/attachment.dart';
import 'attachment_thumbnail.dart';

/// A grid of attachment thumbnails, suitable for image-heavy attachment
/// collections.
class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({
    super.key,
    required this.attachments,
    this.onTapAttachment,
    this.crossAxisCount = 3,
  });

  final List<Attachment> attachments;
  final void Function(Attachment attachment)? onTapAttachment;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return GestureDetector(
          onTap: onTapAttachment == null
              ? null
              : () => onTapAttachment!(attachment),
          child: AttachmentThumbnail(
            attachment: attachment,
            size: double.infinity,
          ),
        );
      },
    );
  }
}
