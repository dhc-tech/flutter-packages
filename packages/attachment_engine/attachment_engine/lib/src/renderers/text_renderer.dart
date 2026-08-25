import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';

/// Plain text viewer. Set [snippetMode] to true (via [TextAttachmentRenderer.preview])
/// for a short, non-scrolling preview rather than the full document.
class TextAttachmentRenderer extends AttachmentRenderer {
  const TextAttachmentRenderer({
    this.snippetMode = false,
    this.snippetLength = 280,
  });

  final bool snippetMode;
  final int snippetLength;

  @override
  AttachmentType get type => AttachmentType.text;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return FutureBuilder<String>(
      future: _readText(attachment),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicatorPlaceholder());
        }
        final text = snapshot.data!;
        final display = snippetMode && text.length > snippetLength
            ? '${text.substring(0, snippetLength)}…'
            : text;
        return snippetMode
            ? Text(display, maxLines: 3, overflow: TextOverflow.ellipsis)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(display),
              );
      },
    );
  }

  Future<String> _readText(Attachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return '';
    try {
      return await File(path).readAsString();
    } catch (_) {
      return '';
    }
  }
}

/// Minimal loading placeholder to avoid pulling in Material just for a spinner.
class CircularProgressIndicatorPlaceholder extends StatelessWidget {
  const CircularProgressIndicatorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 24, height: 24);
}
