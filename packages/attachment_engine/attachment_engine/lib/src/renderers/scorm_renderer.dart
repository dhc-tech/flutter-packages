// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_paths_channel.dart';
import 'archive_renderer.dart';
import 'html_renderer.dart';
import 'renderer.dart';
import 'unknown_renderer.dart';

/// Detects a SCORM package (a zip containing `imsmanifest.xml`), extracts
/// it safely into an app-private directory (guarding against zip-slip path
/// traversal via [extractArchiveSafely]), and launches its entry HTML in
/// [HtmlAttachmentRenderer]. Falls back to [UnknownAttachmentRenderer]'s
/// external-open affordance if the package can't be resolved.
///
/// Known limitation: this locates and displays the SCORM entry HTML, but
/// does not implement a SCORM RTE (runtime environment) / API adapter for
/// tracking (cmi.*) calls - see README "Known limitations".
class ScormAttachmentRenderer extends AttachmentRenderer {
  const ScormAttachmentRenderer();

  @override
  AttachmentType get type => AttachmentType.scorm;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return FutureBuilder<Attachment?>(
      future: _prepare(attachment),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(width: 24, height: 24);
        final launchable = snapshot.data;
        if (launchable == null) {
          return const UnknownAttachmentRenderer().build(context, attachment);
        }
        return const HtmlAttachmentRenderer().build(context, launchable);
      },
    );
  }

  Future<Attachment?> _prepare(Attachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return null;
    try {
      final archiveFile = File(path);
      if (!await archiveContainsScormManifest(archiveFile)) return null;

      final supportDir = await NativePathsChannel.applicationSupportDirectory();
      final targetDir = Directory(
        '${supportDir.path}/scorm_${attachment.stableIdentity}',
      );
      final extracted = await extractArchiveSafely(archiveFile, targetDir);

      final entry = extracted.firstWhere(
        (p) =>
            p.toLowerCase().endsWith('index.html') ||
            p.toLowerCase().endsWith('index_lms.html'),
        orElse: () => extracted.firstWhere(
          (p) => p.toLowerCase().endsWith('.html'),
          orElse: () => '',
        ),
      );
      if (entry.isEmpty) return null;
      return attachment.copyWith(localPath: entry);
    } catch (_) {
      return null;
    }
  }
}
