// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../archive/zip_reader.dart';
import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';

/// Safely extracts a zip [archiveFile] into [targetDir], rejecting any
/// entry that could escape the target directory via `..`, an absolute
/// path, or a symlink. Returns the list of extracted file paths.
///
/// This guard is security-critical: without it, a malicious archive could
/// write files anywhere on disk the app process has access to
/// ("zip slip").
///
/// Pass an already-decoded [reader] (e.g. one built for an earlier check
/// against the same file, such as [archiveContainsScormManifest]'s reader
/// via [archiveReaderContainsScormManifest]) to avoid re-reading and
/// re-decoding the whole archive here — otherwise it's read fresh from
/// [archiveFile].
Future<List<String>> extractArchiveSafely(
  File archiveFile,
  Directory targetDir, {
  ZipReader? reader,
}) async {
  final zipReader =
      reader ?? ZipReader.decodeBytes(await archiveFile.readAsBytes());
  final targetRoot = targetDir.absolute.path;
  final extracted = <String>[];

  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  for (final entry in zipReader.entries) {
    if (entry.isSymlink) {
      continue; // Reject symlink entries outright.
    }
    final name = entry.name;
    if (name.contains('..') || name.startsWith('/') || name.startsWith(r'\')) {
      continue; // Reject traversal / absolute-path entries.
    }

    final outPath = '$targetRoot${Platform.pathSeparator}$name';
    final normalized = File(outPath).absolute.path;
    if (!normalized.startsWith(targetRoot)) {
      continue; // Defense in depth: resolved path escaped target dir.
    }

    if (entry.isDirectory) {
      await Directory(normalized).create(recursive: true);
    } else {
      final outFile = File(normalized);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(zipReader.readBytes(entry));
      extracted.add(normalized);
    }
  }
  return extracted;
}

/// Returns true if [reader]'s archive contains an `imsmanifest.xml` at
/// (or near) its root, indicating a SCORM package. Use this (rather than
/// [archiveContainsScormManifest]) when you already have a decoded
/// [ZipReader] for the file — e.g. because you're about to pass it to
/// [extractArchiveSafely] too — to avoid reading and decoding the whole
/// archive a second time.
bool archiveReaderContainsScormManifest(ZipReader reader) {
  return reader.entries.any(
    (e) => e.name.toLowerCase().endsWith('imsmanifest.xml'),
  );
}

/// Returns true if [archiveFile] contains an `imsmanifest.xml` at (or near)
/// its root, indicating a SCORM package.
Future<bool> archiveContainsScormManifest(File archiveFile) async {
  final bytes = await archiveFile.readAsBytes();
  return archiveReaderContainsScormManifest(ZipReader.decodeBytes(bytes));
}

/// Inspects a zip archive's contents and routes to SCORM/H5P handling, or
/// offers a safe-extraction / external-open fallback for a generic zip.
class ArchiveAttachmentRenderer extends AttachmentRenderer {
  const ArchiveAttachmentRenderer();

  @override
  AttachmentType get type => .archive;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final path = attachment.localPath;
    if (path == null) {
      return const Center(child: Text('Archive unavailable'));
    }
    return FutureBuilder<List<ZipEntry>>(
      future: _listEntries(path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: SizedBox(width: 24, height: 24));
        }
        final entries = snapshot.data!;
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) => Text(entries[index].name),
        );
      },
    );
  }

  Future<List<ZipEntry>> _listEntries(String path) async {
    final bytes = await File(path).readAsBytes();
    return ZipReader.decodeBytes(bytes).entries;
  }
}
