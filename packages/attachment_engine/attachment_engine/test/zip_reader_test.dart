// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/src/archive/zip_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal valid ZIP (STORED entries only) containing [entries]
/// (name -> content), for testing without needing the `archive` package or
/// an external `zip` binary. Mirrors the equivalent single-entry helper in
/// archive_security_test.dart, generalized to multiple entries.
Uint8List _buildStoredZip(Map<String, List<int>> entries) {
  final out = BytesBuilder();
  void writeUint16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
  void writeUint32(int v) =>
      out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

  final localHeaderOffsets = <String, int>{};
  entries.forEach((name, content) {
    localHeaderOffsets[name] = out.length;
    final nameBytes = name.codeUnits;
    writeUint32(0x04034b50);
    writeUint16(20);
    writeUint16(0);
    writeUint16(0); // stored
    writeUint16(0);
    writeUint16(0);
    writeUint32(0);
    writeUint32(content.length);
    writeUint32(content.length);
    writeUint16(nameBytes.length);
    writeUint16(0);
    out.add(nameBytes);
    out.add(content);
  });

  final centralDirStart = out.length;
  entries.forEach((name, content) {
    final nameBytes = name.codeUnits;
    writeUint32(0x02014b50);
    writeUint16(20);
    writeUint16(20);
    writeUint16(0);
    writeUint16(0);
    writeUint16(0);
    writeUint16(0);
    writeUint32(0);
    writeUint32(content.length);
    writeUint32(content.length);
    writeUint16(nameBytes.length);
    writeUint16(0); // extra len
    writeUint16(0); // comment len
    writeUint16(0); // disk number
    writeUint16(0); // internal attrs
    writeUint32(0); // external attrs
    writeUint32(localHeaderOffsets[name]!);
    out.add(nameBytes);
  });
  final centralDirSize = out.length - centralDirStart;

  writeUint32(0x06054b50);
  writeUint16(0);
  writeUint16(0);
  writeUint16(entries.length);
  writeUint16(entries.length);
  writeUint32(centralDirSize);
  writeUint32(centralDirStart);
  writeUint16(0);

  return out.toBytes();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zip_reader_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ZipReader.listEntries', () {
    test('matches decodeBytes().entries for a multi-entry archive', () async {
      final zipBytes = _buildStoredZip({
        'a.txt': 'hello'.codeUnits,
        'dir/b.txt': 'world'.codeUnits,
        'dir/': const [],
      });
      final file = File('${tempDir.path}/multi.zip')
        ..writeAsBytesSync(zipBytes);

      final viaList = await ZipReader.listEntries(file);
      final viaDecode = ZipReader.decodeBytes(zipBytes).entries;

      expect(viaList.map((e) => e.name).toList(), [
        'a.txt',
        'dir/b.txt',
        'dir/',
      ]);
      expect(viaList.length, viaDecode.length);
      for (var i = 0; i < viaList.length; i++) {
        expect(viaList[i].name, viaDecode[i].name);
        expect(viaList[i].isDirectory, viaDecode[i].isDirectory);
        expect(viaList[i].uncompressedSize, viaDecode[i].uncompressedSize);
      }
    });

    test(
      'still lists entries correctly when a large entry\'s content bytes '
      'in the file are corrupted — proving listEntries never reads them',
      () async {
        final bigContent = List<int>.filled(2 * 1024 * 1024, 0x41); // 2 MB
        final zipBytes = _buildStoredZip({
          'big.bin': bigContent,
          'small.txt': 'hi'.codeUnits,
        });
        final file = File('${tempDir.path}/big.zip')
          ..writeAsBytesSync(zipBytes);

        // Corrupt the middle of the file — squarely inside 'big.bin''s
        // content region, nowhere near the tail (EOCD/central directory).
        final raf = file.openSync(mode: FileMode.writeOnlyAppend);
        raf.setPositionSync(zipBytes.length ~/ 2);
        raf.writeFromSync(List<int>.filled(1000, 0xff));
        raf.closeSync();

        final entries = await ZipReader.listEntries(file);

        expect(entries.map((e) => e.name).toList(), ['big.bin', 'small.txt']);
        expect(
          entries.firstWhere((e) => e.name == 'big.bin').uncompressedSize,
          2 * 1024 * 1024,
        );
      },
    );

    test('handles an archive with no entries', () async {
      final zipBytes = _buildStoredZip(const {});
      final file = File('${tempDir.path}/empty.zip')
        ..writeAsBytesSync(zipBytes);

      final entries = await ZipReader.listEntries(file);

      expect(entries, isEmpty);
    });

    test('throws FormatException for a non-zip file', () async {
      final file = File('${tempDir.path}/not-a-zip.txt')
        ..writeAsStringSync('just some text, not a zip archive at all');

      expect(
        () => ZipReader.listEntries(file),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
