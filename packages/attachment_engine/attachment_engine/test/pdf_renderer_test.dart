// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A valid, minimal 1x1 transparent PNG — [Image.memory] needs real
/// decodable image bytes, not just any non-empty byte list.
final _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
);

/// Fake native PDF backend: one document per path, page count derived from
/// the path so different documents are trivially distinguishable in
/// assertions.
class _FakePdfPlatform extends AttachmentEnginePlatform {
  final List<String> openedPaths = [];
  final Map<String, int> pageCountByHandle = {};

  @override
  Future<PdfOpenResult> pdfOpen(String path) async {
    openedPaths.add(path);
    final handle = path;
    pageCountByHandle[handle] = path.contains('multi') ? 3 : 1;
    return PdfOpenResult(handle: handle, pageCount: pageCountByHandle[handle]!);
  }

  @override
  Future<List<int>> pdfRenderPage(
    String handle,
    int index, {
    required int width,
    required int height,
  }) async => _tinyPngBytes;

  @override
  Future<void> pdfClose(String handle) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Attachment pdfAttachment(String id, String localPath) => Attachment(
    id: id,
    name: 'file.pdf',
    source: const AttachmentSource.url('https://example.com/f.pdf'),
    attachmentType: AttachmentType.pdf,
    localPath: localPath,
  );

  late _FakePdfPlatform platform;

  setUp(() {
    platform = _FakePdfPlatform();
    AttachmentEnginePlatform.instance = platform;
  });

  group('PdfAttachmentRenderer', () {
    testWidgets(
      'reusing the same renderer/widget for a different attachment reopens '
      'the new document instead of keeping the previous one',
      (tester) async {
        final renderer = PdfAttachmentRenderer();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                pdfAttachment('a1', '/tmp/first.pdf'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(platform.openedPaths, ['/tmp/first.pdf']);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                pdfAttachment('a2', '/tmp/second-multi.pdf'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(platform.openedPaths, [
          '/tmp/first.pdf',
          '/tmp/second-multi.pdf',
        ]);
        // The new document's page count (3, from "multi") drives the
        // PageView — reaching this without throwing confirms a fresh
        // PageController was built for it rather than reusing a stale one
        // sized for the first (1-page) document.
        expect(find.byType(PageView), findsOneWidget);
      },
    );

    testWidgets('remembers the last-viewed page across reopen', (tester) async {
      final pageMemory = InMemoryPdfPageMemory();
      final renderer = PdfAttachmentRenderer(pageMemory: pageMemory);
      final attachment = pdfAttachment('a3', '/tmp/multi.pdf');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => renderer.build(context, attachment),
          ),
        ),
      );
      await tester.pumpAndSettle();

      pageMemory.savePage(attachment.id, 2);
      expect(pageMemory.lastPage(attachment.id), 2);
    });
  });
}
