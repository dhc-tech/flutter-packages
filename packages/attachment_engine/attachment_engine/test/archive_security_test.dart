// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/src/archive/zip_reader.dart';
import 'package:attachment_engine/src/renderers/archive_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal valid ZIP (STORED entries only, CRC-32 left as 0 since
/// the hand-written [ZipReader] under test does not validate it) containing
/// a single entry named [entryName] with [content], for exercising
/// zip-slip / path-traversal defenses without needing the `archive` package
/// or an external `zip` binary.
Uint8List _buildStoredZip(String entryName, List<int> content) {
  final nameBytes = entryName.codeUnits;
  final out = BytesBuilder();

  final localHeaderOffset = 0;

  void writeUint16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
  void writeUint32(int v) =>
      out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

  // Local file header.
  writeUint32(0x04034b50);
  writeUint16(20); // version needed
  writeUint16(0); // flags
  writeUint16(0); // method: stored
  writeUint16(0); // mod time
  writeUint16(0); // mod date
  writeUint32(0); // crc32 (unchecked by reader)
  writeUint32(content.length); // compressed size
  writeUint32(content.length); // uncompressed size
  writeUint16(nameBytes.length);
  writeUint16(0); // extra len
  out.add(nameBytes);
  out.add(content);

  final centralDirStart = out.length;

  // Central directory file header.
  writeUint32(0x02014b50);
  writeUint16(20); // version made by (generic, not unix -> not a symlink)
  writeUint16(20); // version needed
  writeUint16(0); // flags
  writeUint16(0); // method
  writeUint16(0); // time
  writeUint16(0); // date
  writeUint32(0); // crc32
  writeUint32(content.length);
  writeUint32(content.length);
  writeUint16(nameBytes.length);
  writeUint16(0); // extra len
  writeUint16(0); // comment len
  writeUint16(0); // disk number
  writeUint16(0); // internal attrs
  writeUint32(0); // external attrs
  writeUint32(localHeaderOffset);
  out.add(nameBytes);

  final centralDirSize = out.length - centralDirStart;

  // End of central directory record.
  writeUint32(0x06054b50);
  writeUint16(0); // disk number
  writeUint16(0); // disk with central dir
  writeUint16(1); // entries on this disk
  writeUint16(1); // total entries
  writeUint32(centralDirSize);
  writeUint32(centralDirStart);
  writeUint16(0); // comment len

  return out.toBytes();
}

void main() {
  group('extractArchiveSafely security guard', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('archive_security_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('rejects a path-traversal entry name (../../etc/passwot)', () async {
      final zipBytes = _buildStoredZip(
        '../../etc/passwot',
        'malicious'.codeUnits,
      );
      final archiveFile = File('${tempDir.path}/malicious.zip')
        ..writeAsBytesSync(zipBytes);
      final targetDir = Directory('${tempDir.path}/extracted')..createSync();

      final extracted = await extractArchiveSafely(archiveFile, targetDir);

      expect(extracted, isEmpty);
      // Confirm nothing escaped the target directory.
      final escaped = File('${tempDir.path}/etc/passwot');
      expect(escaped.existsSync(), isFalse);
    });

    test('rejects an absolute-path entry name', () async {
      final zipBytes = _buildStoredZip('/etc/passwot', 'x'.codeUnits);
      final archiveFile = File('${tempDir.path}/abs.zip')
        ..writeAsBytesSync(zipBytes);
      final targetDir = Directory('${tempDir.path}/extracted2')..createSync();

      final extracted = await extractArchiveSafely(archiveFile, targetDir);

      expect(extracted, isEmpty);
    });

    test('extracts a benign entry normally', () async {
      final zipBytes = _buildStoredZip('index.html', '<html></html>'.codeUnits);
      final archiveFile = File('${tempDir.path}/good.zip')
        ..writeAsBytesSync(zipBytes);
      final targetDir = Directory('${tempDir.path}/extracted3')..createSync();

      final extracted = await extractArchiveSafely(archiveFile, targetDir);

      expect(extracted, hasLength(1));
      expect(File(extracted.single).readAsStringSync(), '<html></html>');
    });

    test('a pre-built reader is used as-is, without re-reading the file '
        '(SCORM detection + extraction share one read+decode)', () async {
      final zipBytes = _buildStoredZip('index.html', '<html></html>'.codeUnits);
      final archiveFile = File('${tempDir.path}/reused.zip')
        ..writeAsBytesSync(zipBytes);
      final reader = ZipReader.decodeBytes(zipBytes);

      // Corrupt the file on disk after building the reader — if
      // extractArchiveSafely still needed to re-read/re-decode the file
      // itself instead of using the passed reader, this extraction
      // would now fail (or produce garbage).
      archiveFile.writeAsBytesSync([0, 0, 0]);

      final targetDir = Directory('${tempDir.path}/extracted4')..createSync();
      final extracted = await extractArchiveSafely(
        archiveFile,
        targetDir,
        reader: reader,
      );

      expect(extracted, hasLength(1));
      expect(File(extracted.single).readAsStringSync(), '<html></html>');
    });
  });

  group('archiveReaderContainsScormManifest', () {
    test('true when imsmanifest.xml is present', () {
      final zipBytes = _buildStoredZip(
        'imsmanifest.xml',
        '<manifest/>'.codeUnits,
      );
      final reader = ZipReader.decodeBytes(zipBytes);

      expect(archiveReaderContainsScormManifest(reader), isTrue);
    });

    test('false when no manifest entry is present', () {
      final zipBytes = _buildStoredZip('index.html', '<html/>'.codeUnits);
      final reader = ZipReader.decodeBytes(zipBytes);

      expect(archiveReaderContainsScormManifest(reader), isFalse);
    });
  });
}
