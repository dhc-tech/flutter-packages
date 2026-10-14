// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(List<int> v) => Uint8List.fromList(v);

void main() {
  const detector = FormatDetector();

  group('FormatDetector explicit mime types', () {
    const cases = <String, AttachmentType>{
      'image/png': AttachmentType.image,
      'IMAGE/JPEG': AttachmentType.image,
      'video/mp4': AttachmentType.video,
      'audio/mpeg': AttachmentType.audio,
      'application/pdf': AttachmentType.pdf,
      'text/html': AttachmentType.html,
      'text/html; charset=utf-8': AttachmentType.html,
      'text/csv': AttachmentType.csv,
      'application/csv': AttachmentType.csv,
      'text/tab-separated-values': AttachmentType.csv,
      'text/plain': AttachmentType.text,
      'text/markdown': AttachmentType.text,
      'application/zip': AttachmentType.archive,
      'application/x-zip-compressed': AttachmentType.archive,
      'application/x-7z-compressed': AttachmentType.archive,
      'application/x-rar-compressed': AttachmentType.archive,
      'application/x-tar': AttachmentType.archive,
      'application/gzip': AttachmentType.archive,
      'application/msword': AttachmentType.office,
      'application/vnd.ms-excel': AttachmentType.office,
      'application/vnd.ms-powerpoint': AttachmentType.office,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
          AttachmentType.office,
      'application/vnd.oasis.opendocument.text': AttachmentType.office,
      '  application/pdf  ': AttachmentType.pdf,
    };
    for (final e in cases.entries) {
      test('"${e.key}" -> ${e.value.name}', () {
        expect(detector.detect(explicitMimeType: e.key), e.value);
      });
    }

    test('unrecognised, empty and garbage mime types yield unknown', () {
      expect(
        detector.detect(explicitMimeType: 'application/x-nothing'),
        AttachmentType.unknown,
      );
      expect(detector.detect(explicitMimeType: ''), AttachmentType.unknown);
      expect(detector.detect(explicitMimeType: ';;;'), AttachmentType.unknown);
    });

    test('an unrecognised mime falls through to the other signals', () {
      expect(
        detector.detect(
          explicitMimeType: 'application/octet-stream',
          extension: 'pdf',
        ),
        AttachmentType.pdf,
      );
    });
  });

  group('FormatDetector extensions', () {
    const cases = <String, AttachmentType>{
      'docx': AttachmentType.office,
      'XLSX': AttachmentType.office,
      '.pptx': AttachmentType.office,
      'rtf': AttachmentType.office,
      'odp': AttachmentType.office,
      'pdf': AttachmentType.pdf,
      'csv': AttachmentType.csv,
      'tsv': AttachmentType.csv,
      'txt': AttachmentType.text,
      'md': AttachmentType.text,
      'json': AttachmentType.text,
      'yaml': AttachmentType.text,
      'html': AttachmentType.html,
      'htm': AttachmentType.html,
      'zip': AttachmentType.archive,
      '7z': AttachmentType.archive,
      'scorm': AttachmentType.scorm,
      'h5p': AttachmentType.h5p,
      'png': AttachmentType.image,
      'heic': AttachmentType.image,
      'mp4': AttachmentType.video,
      'mkv': AttachmentType.video,
      'mp3': AttachmentType.audio,
    };
    for (final e in cases.entries) {
      test('"${e.key}" -> ${e.value.name}', () {
        expect(detector.detect(extension: e.key), e.value);
      });
    }

    test('unknown or empty extension yields unknown', () {
      expect(detector.detect(extension: 'qqq'), AttachmentType.unknown);
      expect(detector.detect(extension: ''), AttachmentType.unknown);
      expect(detector.detect(extension: '.'), AttachmentType.unknown);
    });

    test('nothing at all is unknown, empty bytes are ignored', () {
      expect(detector.detect(), AttachmentType.unknown);
      expect(detector.detect(bytes: Uint8List(0)), AttachmentType.unknown);
    });
  });

  group('FormatDetector url handling', () {
    test('uses the url path extension and ignores query and fragment', () {
      expect(
        detector.detect(url: 'https://x.com/a/report.PDF?sig=abc.def#frag'),
        AttachmentType.pdf,
      );
    });

    test('a dot only in the host, a trailing slash, or no dot is not an '
        'extension', () {
      expect(
        detector.detect(url: 'https://x.com/download'),
        AttachmentType.unknown,
      );
      expect(
        detector.detect(url: 'https://x.com/dir.v2/file'),
        AttachmentType.unknown,
      );
      expect(detector.detect(url: 'https://x.com/'), AttachmentType.unknown);
      expect(detector.detect(url: ''), AttachmentType.unknown);
    });

    test('an unparsable url falls back to treating it as a path', () {
      expect(
        detector.detect(url: 'http://[bad/file.png'),
        AttachmentType.image,
      );
    });

    test('an unknown url extension falls through to content-type', () {
      expect(
        detector.detect(
          url: 'https://x.com/a.weird',
          httpContentType: 'application/pdf',
        ),
        AttachmentType.pdf,
      );
    });
  });

  group('FormatDetector priority', () {
    test('extension beats url, url beats http content type', () {
      expect(
        detector.detect(
          extension: 'csv',
          url: 'https://x/a.pdf',
          httpContentType: 'image/png',
        ),
        AttachmentType.csv,
      );
      expect(
        detector.detect(url: 'https://x/a.pdf', httpContentType: 'image/png'),
        AttachmentType.pdf,
      );
    });

    test('a generic text mime loses to a more specific http content type', () {
      expect(
        detector.detect(
          explicitMimeType: 'text/plain',
          httpContentType: 'application/pdf',
        ),
        AttachmentType.pdf,
      );
    });

    test('a generic text mime loses to magic bytes', () {
      expect(
        detector.detect(
          explicitMimeType: 'text/plain',
          bytes: _b([0x89, 0x50, 0x4E, 0x47, 0, 0]),
        ),
        AttachmentType.image,
      );
    });

    test('zip bytes with scorm/office/other extensions', () {
      final zip = _b([0x50, 0x4B, 0x03, 0x04, 0, 0]);
      expect(
        detector.detect(bytes: zip, extension: 'scorm'),
        AttachmentType.scorm,
      );
      expect(
        detector.detect(bytes: zip, extension: 'xlsx'),
        AttachmentType.office,
      );
      expect(
        detector.detect(bytes: zip, extension: 'zip'),
        AttachmentType.archive,
      );
      expect(
        detector.detect(bytes: zip, extension: 'h5p'),
        AttachmentType.archive,
      );
      expect(detector.detect(bytes: zip), AttachmentType.archive);
    });

    test('magic bytes beat a misleading extension', () {
      expect(
        detector.detect(
          bytes: _b([0x25, 0x50, 0x44, 0x46, 0]),
          extension: 'txt',
        ),
        AttachmentType.pdf,
      );
    });
  });

  group('detectTypeFromMagicBytes', () {
    test('every signature type is recognised', () {
      expect(
        detectTypeFromMagicBytes(_b([0xFF, 0xD8, 0xFF, 0xE0])),
        AttachmentType.image,
      );
      expect(
        detectTypeFromMagicBytes(_b([0x47, 0x49, 0x46, 0x38, 0x39])),
        AttachmentType.image,
      );
      expect(
        detectTypeFromMagicBytes(_b([0x25, 0x50, 0x44, 0x46])),
        AttachmentType.pdf,
      );
      expect(
        detectTypeFromMagicBytes(_b([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70])),
        AttachmentType.video,
      );
      expect(
        detectTypeFromMagicBytes(_b([0x49, 0x44, 0x33, 4])),
        AttachmentType.audio,
      );
      expect(
        detectTypeFromMagicBytes(_b([0xFF, 0xFB, 0x90])),
        AttachmentType.audio,
      );
      expect(
        detectTypeFromMagicBytes(_b([0x50, 0x4B, 0x05, 0x06])),
        AttachmentType.archive,
      );
    });

    test('RIFF is disambiguated by its format tag; others and short RIFF are '
        'unknown', () {
      List<int> riff(String tag) => [
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        ...tag.codeUnits,
      ];
      expect(detectTypeFromMagicBytes(_b(riff('WEBP'))), AttachmentType.image);
      expect(detectTypeFromMagicBytes(_b(riff('WAVE'))), AttachmentType.audio);
      expect(detectTypeFromMagicBytes(_b(riff('AVI '))), isNull);
      expect(
        detectTypeFromMagicBytes(_b([0x52, 0x49, 0x46, 0x46, 1, 2])),
        isNull,
      );
    });

    test('empty, too-short and unrecognised buffers return null', () {
      expect(detectTypeFromMagicBytes(Uint8List(0)), isNull);
      expect(detectTypeFromMagicBytes(_b([0x89])), isNull);
      expect(detectTypeFromMagicBytes(_b([1, 2, 3, 4, 5, 6])), isNull);
      expect(detectTypeFromMagicBytes(_b([0x66, 0x74, 0x79, 0x70])), isNull);
    });

    test('MagicSignature honours its offset and length bounds', () {
      const sig = MagicSignature(AttachmentType.video, [1, 2], offset: 3);
      expect(sig.matches(_b([0, 0, 0, 1, 2])), isTrue);
      expect(sig.matches(_b([0, 0, 0, 1])), isFalse);
      expect(sig.matches(_b([1, 2, 0, 0, 0])), isFalse);
    });
  });

  group('lookupMimeTypeForExtension', () {
    test('accepts bare extensions, file names and any casing', () {
      expect(lookupMimeTypeForExtension('png'), 'image/png');
      expect(lookupMimeTypeForExtension('PNG'), 'image/png');
      expect(lookupMimeTypeForExtension('photo.final.JPG'), 'image/jpeg');
      expect(lookupMimeTypeForExtension('.pdf'), 'application/pdf');
    });

    test('unknown or empty input returns null', () {
      expect(lookupMimeTypeForExtension('zzz'), isNull);
      expect(lookupMimeTypeForExtension(''), isNull);
      expect(lookupMimeTypeForExtension('noextension.'), isNull);
    });
  });
}
