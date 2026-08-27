// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:attachment_engine/src/util/chunked_file_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chunked_file_reader_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('readFileInChunks', () {
    test('matches readAsBytes for a file smaller than one chunk', () async {
      final file = File('${tempDir.path}/small.bin')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      final result = await readFileInChunks(file.path, chunkSize: 65536);

      expect(result, [1, 2, 3, 4, 5]);
    });

    test(
      'matches readAsBytes for a file spanning multiple small chunks',
      () async {
        final random = Random(42);
        final bytes = Uint8List.fromList(
          List.generate(10000, (_) => random.nextInt(256)),
        );
        final file = File('${tempDir.path}/multi.bin')..writeAsBytesSync(bytes);

        // A deliberately tiny chunk size so this genuinely exercises
        // multiple read() calls for a 10,000-byte file.
        final result = await readFileInChunks(file.path, chunkSize: 777);

        expect(result, bytes);
      },
    );

    test('returns an empty list for an empty file', () async {
      final file = File('${tempDir.path}/empty.bin')..writeAsBytesSync([]);

      final result = await readFileInChunks(file.path);

      expect(result, isEmpty);
    });
  });

  group('readFileAsBase64Chunked', () {
    test(
      'matches base64Encode(readAsBytes()) for a multi-chunk file',
      () async {
        final random = Random(7);
        final bytes = Uint8List.fromList(
          List.generate(20000, (_) => random.nextInt(256)),
        );
        final file = File('${tempDir.path}/data.bin')..writeAsBytesSync(bytes);

        final chunked = await readFileAsBase64Chunked(
          file.path,
          chunkSize: 999,
        );

        expect(chunked, base64Encode(bytes));
      },
    );

    test('matches for a file smaller than one chunk', () async {
      final bytes = utf8.encode('hello world');
      final file = File('${tempDir.path}/small.bin')..writeAsBytesSync(bytes);

      final chunked = await readFileAsBase64Chunked(file.path);

      expect(chunked, base64Encode(bytes));
    });

    test('returns an empty string for an empty file', () async {
      final file = File('${tempDir.path}/empty.bin')..writeAsBytesSync([]);

      final chunked = await readFileAsBase64Chunked(file.path);

      expect(chunked, '');
    });
  });

  group('readTextSnippet', () {
    test('returns the whole content when under maxBytes', () async {
      final file = File('${tempDir.path}/short.txt')
        ..writeAsStringSync('hello world');

      final snippet = await readTextSnippet(file.path, maxBytes: 65536);

      expect(snippet, 'hello world');
    });

    test('reads only the first maxBytes of a larger file', () async {
      final file = File('${tempDir.path}/long.txt')
        ..writeAsStringSync('abcdefghij' * 100); // 1000 ASCII bytes

      final snippet = await readTextSnippet(file.path, maxBytes: 26);

      expect(snippet.length, 26);
      expect(snippet, 'abcdefghijabcdefghijabcdef');
    });

    test(
      'does not throw on a UTF-8 multi-byte sequence truncated at the cut',
      () async {
        // "café" — é is 2 UTF-8 bytes (0xC3 0xA9). Cutting after the first
        // byte of é would break naive utf8.decode() without
        // allowMalformed.
        final bytes = utf8.encode('café');
        final file = File('${tempDir.path}/utf8.txt')..writeAsBytesSync(bytes);

        // Cut right in the middle of "é"'s 2-byte encoding.
        final snippet = await readTextSnippet(
          file.path,
          maxBytes: bytes.length - 1,
        );

        expect(() => snippet, returnsNormally);
      },
    );
  });
}
