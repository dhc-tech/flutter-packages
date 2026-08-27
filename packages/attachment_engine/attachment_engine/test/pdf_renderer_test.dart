// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
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

  /// When set, pdfOpen for this exact path waits on this completer before
  /// resolving — used to simulate an in-flight open completing late, after
  /// a newer one has already started.
  String? delayedPath;
  Completer<void>? delayGate;

  @override
  Future<PdfOpenResult> pdfOpen(String path) async {
    if (path == delayedPath) {
      await delayGate!.future;
    }
    openedPaths.add(path);
    final handle = path;
    pageCountByHandle[handle] = path.contains('multi') ? 3 : 1;
    return PdfOpenResult(handle: handle, pageCount: pageCountByHandle[handle]!);
  }

  final List<int> renderedPageIndexes = [];

  @override
  Future<List<int>> pdfRenderPage(
    String handle,
    int index, {
    required int width,
    required int height,
  }) async {
    renderedPageIndexes.add(index);
    return _tinyPngBytes;
  }

  final List<String> closedHandles = [];

  @override
  Future<void> pdfClose(String handle) async {
    closedHandles.add(handle);
  }
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

    testWidgets(
      'a saved page position is honored on open: the PDF opens straight '
      'to that page instead of always restarting at page one',
      (tester) async {
        final pageMemory = InMemoryPdfPageMemory();
        final attachment = pdfAttachment('a3', '/tmp/multi.pdf');
        // Simulate a page position saved by a previous session/viewing —
        // this is the actual behavior being verified, not just that the
        // memory object itself can store and return a value.
        pageMemory.savePage(attachment.id, 2);
        final renderer = PdfAttachmentRenderer(pageMemory: pageMemory);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(context, attachment),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The first page actually rendered is the saved one (index 2),
        // not 0 — proving the PageView/PageController was built with
        // initialPage from pageMemory rather than always starting fresh.
        expect(platform.renderedPageIndexes, isNotEmpty);
        expect(platform.renderedPageIndexes.first, 2);
      },
    );

    testWidgets(
      'changing pages saves the new position for a later open to pick up',
      (tester) async {
        final pageMemory = InMemoryPdfPageMemory();
        final attachment = pdfAttachment('a3', '/tmp/multi.pdf');
        final renderer = PdfAttachmentRenderer(pageMemory: pageMemory);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(context, attachment),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(platform.renderedPageIndexes.first, 0);

        final pageView = tester.widget<PageView>(find.byType(PageView));
        pageView.controller!.jumpToPage(2);
        await tester.pumpAndSettle();

        expect(pageMemory.lastPage(attachment.id), 2);
      },
    );

    testWidgets(
      'a slow-to-open previous document completing late does not clobber '
      'the newer document already showing',
      (tester) async {
        platform.delayedPath = '/tmp/slow.pdf';
        platform.delayGate = Completer<void>();
        final renderer = PdfAttachmentRenderer();

        // Start opening the first (slow) document — its pdfOpen() call
        // hangs on delayGate and never resolves during this pump.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, pdfAttachment('a1', '/tmp/slow.pdf')),
            ),
          ),
        );
        await tester.pump();

        // Reuse the same widget for a different (fast) attachment before
        // the first open has resolved.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                pdfAttachment('a2', '/tmp/fast-multi.pdf'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(platform.openedPaths, ['/tmp/fast-multi.pdf']);
        expect(find.byType(PageView), findsOneWidget);

        // Now let the slow, stale open resolve.
        platform.delayGate!.complete();
        await tester.pumpAndSettle();

        // The fix: the stale controller is closed instead of overwriting
        // the (already-showing) newer one.
        expect(platform.openedPaths, ['/tmp/fast-multi.pdf', '/tmp/slow.pdf']);
        expect(platform.closedHandles, contains('/tmp/slow.pdf'));
        expect(find.byType(PageView), findsOneWidget);
      },
    );
  });
}
