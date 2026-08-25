// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

/// A single entry (file or directory) parsed from a ZIP central directory.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.isDirectory,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.isSymlink,
  });

  final String name;
  final bool isDirectory;

  /// 0 = stored (no compression), 8 = deflate.
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final bool isSymlink;
}

/// Minimal hand-written ZIP reader that parses the End-Of-Central-Directory
/// record and Central Directory File Headers to list entries, and reads
/// individual entries' bytes via their Local File Header, using
/// [ZLibDecoder] (raw-deflate mode) from `dart:io` (SDK-provided) for
/// DEFLATE decompression. Supports STORED (0) and DEFLATE (8) methods
/// only, which covers the overwhelming majority of zip/SCORM/office
/// packages in practice.
///
/// This replaces the third-party `archive` package.
class ZipReader {
  ZipReader._(this._bytes, this.entries);

  final Uint8List _bytes;
  final List<ZipEntry> entries;

  static const int _centralDirSignature = 0x02014b50;
  static const int _localHeaderSignature = 0x04034b50;

  /// Parses [bytes] as a zip archive's central directory.
  factory ZipReader.decodeBytes(Uint8List bytes) {
    final eocdOffset = _findEocd(bytes);
    if (eocdOffset == -1) {
      throw const FormatException('Not a valid zip archive (no EOCD found)');
    }
    final bd = ByteData.sublistView(bytes);
    final totalEntries = bd.getUint16(eocdOffset + 10, Endian.little);
    var centralDirOffset = bd.getUint32(eocdOffset + 16, Endian.little);

    final entries = <ZipEntry>[];
    for (var i = 0; i < totalEntries; i++) {
      final sig = bd.getUint32(centralDirOffset, Endian.little);
      if (sig != _centralDirSignature) break;
      final versionMadeBy = bd.getUint16(centralDirOffset + 4, Endian.little);
      final compressionMethod = bd.getUint16(
        centralDirOffset + 10,
        Endian.little,
      );
      final compressedSize = bd.getUint32(centralDirOffset + 20, Endian.little);
      final uncompressedSize = bd.getUint32(
        centralDirOffset + 24,
        Endian.little,
      );
      final nameLen = bd.getUint16(centralDirOffset + 28, Endian.little);
      final extraLen = bd.getUint16(centralDirOffset + 30, Endian.little);
      final commentLen = bd.getUint16(centralDirOffset + 32, Endian.little);
      final externalAttrs = bd.getUint32(centralDirOffset + 38, Endian.little);
      final localHeaderOffset = bd.getUint32(
        centralDirOffset + 42,
        Endian.little,
      );
      final nameStart = centralDirOffset + 46;
      final name = String.fromCharCodes(
        bytes.sublist(nameStart, nameStart + nameLen),
      );

      // Unix symlink bit: upper 16 bits of externalAttrs hold unix file
      // mode when the "version made by" upper byte indicates unix (3).
      final unixMode = externalAttrs >> 16;
      final isSymlink =
          (versionMadeBy >> 8) == 3 && (unixMode & 0xA000) == 0xA000;

      entries.add(
        ZipEntry(
          name: name,
          isDirectory: name.endsWith('/'),
          compressionMethod: compressionMethod,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          localHeaderOffset: localHeaderOffset,
          isSymlink: isSymlink,
        ),
      );

      centralDirOffset = nameStart + nameLen + extraLen + commentLen;
    }
    return ZipReader._(bytes, entries);
  }

  /// Reads and (if needed) decompresses the content of [entry].
  Uint8List readBytes(ZipEntry entry) {
    final bd = ByteData.sublistView(_bytes);
    final offset = entry.localHeaderOffset;
    final sig = bd.getUint32(offset, Endian.little);
    if (sig != _localHeaderSignature) {
      throw const FormatException('Invalid local file header');
    }
    final nameLen = bd.getUint16(offset + 26, Endian.little);
    final extraLen = bd.getUint16(offset + 28, Endian.little);
    final dataStart = offset + 30 + nameLen + extraLen;
    final compressed = _bytes.sublist(
      dataStart,
      dataStart + entry.compressedSize,
    );

    switch (entry.compressionMethod) {
      case 0:
        return compressed;
      case 8:
        return Uint8List.fromList(ZLibDecoder(raw: true).convert(compressed));
      default:
        throw FormatException(
          'Unsupported zip compression method ${entry.compressionMethod}',
        );
    }
  }

  static int _findEocd(Uint8List bytes) {
    // EOCD is at least 22 bytes, and may be followed by a comment of up
    // to 65535 bytes, so scan backward from the end.
    final minOffset = bytes.length >= 22 + 65535
        ? bytes.length - 22 - 65535
        : 0;
    for (var i = bytes.length - 22; i >= minOffset; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    return -1;
  }
}
