import 'package:flutter/material.dart';

import '../models/attachment.dart';
import 'attachment_tile.dart';

/// A vertical list of [AttachmentTile]s.
class AttachmentList extends StatelessWidget {
  const AttachmentList({
    super.key,
    required this.attachments,
    this.onTapAttachment,
  });

  final List<Attachment> attachments;
  final void Function(Attachment attachment)? onTapAttachment;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: attachments.length,
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return AttachmentTile(
          attachment: attachment,
          onTap: onTapAttachment == null
              ? null
              : () => onTapAttachment!(attachment),
        );
      },
    );
  }
}
