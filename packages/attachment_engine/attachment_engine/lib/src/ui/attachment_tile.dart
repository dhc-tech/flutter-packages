// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_failure.dart';
import 'attachment_thumbnail.dart';

/// A single row representing an [Attachment] in a list, showing a
/// thumbnail, name, and a state-dependent trailing widget (spinner while
/// loading, error icon on failure, or a chevron when ready).
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    this.isLoading = false,
    this.failure,
    this.onTap,
  });

  final Attachment attachment;
  final bool isLoading;
  final AttachmentFailure? failure;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('attachment_tile'),
      leading: AttachmentThumbnail(attachment: attachment),
      title: Text(attachment.name),
      subtitle: failure != null
          ? Text(
              failure!.localizedMessage,
              key: const Key('attachment_tile_error_text'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          : null,
      trailing: _trailing(context),
      onTap: onTap,
    );
  }

  Widget? _trailing(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        key: Key('attachment_tile_loading'),
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (failure != null) {
      return Icon(
        Icons.error_outline,
        key: const Key('attachment_tile_error_icon'),
        color: Theme.of(context).colorScheme.error,
      );
    }
    return const Icon(Icons.chevron_right, key: Key('attachment_tile_ready'));
  }
}
