// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = FormatDetector();

  group('FormatDetector priority order', () {
    test('explicit mime type wins over everything else', () {
      final type = detector.detect(
        explicitMimeType: 'image/png',
        bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), // %PDF magic bytes
        extension: 'mp3',
      );
      expect(type, AttachmentType.image);
    });

    test('magic bytes win over extension when no explicit mime', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([
          0x25,
          0x50,
          0x44,
          0x46,
          0x2D,
          0x31,
        ]), // %PDF-1
        extension: 'txt',
      );
      expect(type, AttachmentType.pdf);
    });

    test('extension used when bytes are inconclusive', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0, 0, 0, 0]),
        extension: 'pdf',
      );
      expect(type, AttachmentType.pdf);
    });

    test('url extension used as fallback', () {
      final type = detector.detect(
        url: 'https://example.com/path/to/file.mp4?sig=abc',
      );
      expect(type, AttachmentType.video);
    });

    test('http content-type used as last resort', () {
      final type = detector.detect(httpContentType: 'application/pdf');
      expect(type, AttachmentType.pdf);
    });

    test('unknown when nothing matches', () {
      final type = detector.detect();
      expect(type, AttachmentType.unknown);
    });
  });

  group('magic bytes signature table', () {
    test('detects PNG', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
      );
      expect(type, AttachmentType.image);
    });

    test('detects JPEG', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      );
      expect(type, AttachmentType.image);
    });

    test('detects GIF', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
      );
      expect(type, AttachmentType.image);
    });

    test('detects ZIP as archive by default', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0]),
      );
      expect(type, AttachmentType.archive);
    });

    test('zip bytes + office extension resolve to office', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0]),
        extension: 'docx',
      );
      expect(type, AttachmentType.office);
    });

    test('detects MP3 via ID3 tag', () {
      final type = detector.detect(
        bytes: Uint8List.fromList([0x49, 0x44, 0x33, 0x03]),
      );
      expect(type, AttachmentType.audio);
    });

    test('detects WAV vs WEBP via RIFF disambiguation', () {
      final wavBytes = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x41,
        0x56,
        0x45,
      ]);
      final webpBytes = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      expect(detector.detect(bytes: wavBytes), AttachmentType.audio);
      expect(detector.detect(bytes: webpBytes), AttachmentType.image);
    });

    test('detects csv extension as csv, not text', () {
      final type = detector.detect(extension: 'csv');
      expect(type, AttachmentType.csv);
    });

    test('detects text/csv mime type as csv, not text', () {
      final type = detector.detect(explicitMimeType: 'text/csv');
      expect(type, AttachmentType.csv);
    });

    test('detects csv via url extension', () {
      final type = detector.detect(
        url: 'https://example.com/export.csv?sig=abc',
      );
      expect(type, AttachmentType.csv);
    });
  });
}
