import 'package:flutter/material.dart';

import '../models/attachment_capabilities.dart';

/// Row of action buttons (share/download/open externally/delete cache)
/// wired to an attachment's [AttachmentCapabilities], so unavailable
/// actions are simply omitted rather than shown disabled.
class AttachmentActions extends StatelessWidget {
  const AttachmentActions({
    super.key,
    required this.capabilities,
    this.onShare,
    this.onDownload,
    this.onOpenExternally,
    this.onDeleteCache,
  });

  final AttachmentCapabilities capabilities;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenExternally;
  final VoidCallback? onDeleteCache;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    if (capabilities.canShare && onShare != null) {
      actions.add(
        IconButton(icon: const Icon(Icons.share), onPressed: onShare),
      );
    }
    if (capabilities.canDownload && onDownload != null) {
      actions.add(
        IconButton(icon: const Icon(Icons.download), onPressed: onDownload),
      );
    }
    if (capabilities.canOpenExternally && onOpenExternally != null) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: onOpenExternally,
        ),
      );
    }
    if (capabilities.canDeleteCache && onDeleteCache != null) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDeleteCache,
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}
