// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/widget_harness.dart';

class _Pdf extends AttachmentEnginePlatform {
  int failOpens = 0;
  int failRenders = 0;
  int pages = 3;
  final List<String> opened = [];
  final List<int> rendered = [];
  final List<String> closed = [];
  final List<(int, int)> sizes = [];

  @override
  Future<PdfOpenResult> pdfOpen(String path) async {
    opened.add(path);
    if (failOpens > 0) {
      failOpens--;
      throw StateError('cannot open');
    }
    return PdfOpenResult(handle: path, pageCount: pages);
  }

  @override
  Future<List<int>> pdfRenderPage(
    String handle,
    int index, {
    required int width,
    required int height,
  }) async {
    rendered.add(index);
    sizes.add((width, height));
    if (failRenders > 0) {
      failRenders--;
      throw StateError('cannot render');
    }
    return kTinyPng;
  }

  @override
  Future<void> pdfClose(String handle) async => closed.add(handle);
}

Attachment _pdf(String id, {String? path = '/tmp/a.pdf'}) => Attachment(
  id: id,
  name: 'f.pdf',
  source: const AttachmentSource.url('https://e.com/f.pdf'),
  attachmentType: AttachmentType.pdf,
  localPath: path,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Pdf platform;

  setUp(() {
    platform = _Pdf();
    AttachmentEnginePlatform.instance = platform;
  });

  Widget host(
    PdfAttachmentRenderer r,
    Attachment a, {
    TextDirection dir = TextDirection.ltr,
  }) => harness(Builder(builder: (c) => r.build(c, a)), textDirection: dir);

  group('InMemoryPdfPageMemory', () {
    test(
      'remembers pages per key, overwrites, and returns null for unknown keys',
      () {
        final m = InMemoryPdfPageMemory();
        expect(m.lastPage('a'), isNull);
        m.savePage('a', 3);
        m.savePage('b', 0);
        m.savePage('a', 5);
        expect(m.lastPage('a'), 5);
        expect(m.lastPage('b'), 0);
        expect(m.lastPage(''), isNull);
      },
    );

    test('the renderer defaults to the shared memory', () {
      expect(PdfAttachmentRenderer().pageMemory, same(defaultPdfPageMemory));
      final custom = InMemoryPdfPageMemory();
      expect(
        PdfAttachmentRenderer(pageMemory: custom).pageMemory,
        same(custom),
      );
    });
  });

  group('PdfAttachmentRenderer', () {
    test(
      'type is pdf',
      () => expect(PdfAttachmentRenderer().type, AttachmentType.pdf),
    );

    testWidgets(
      'no local path shows the unavailable state without opening anything',
      (tester) async {
        await tester.pumpWidget(
          host(PdfAttachmentRenderer(), _pdf('x', path: null)),
        );
        expect(find.text('PDF unavailable'), findsOneWidget);
        expect(platform.opened, isEmpty);
      },
    );

    testWidgets('shows a spinner while opening, then the first page', (
      tester,
    ) async {
      await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('p1')));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.byType(Image), findsOneWidget);
      expect(platform.rendered.first, 0);
    });

    testWidgets(
      'requests a page render sized from the logical size and pixel ratio',
      (tester) async {
        setScreenSize(tester, const Size(300, 500));
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('p2')));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(platform.sizes.first, (300, 500));
      },
    );

    testWidgets(
      'an open failure shows the error and Retry reopens the document',
      (tester) async {
        platform.failOpens = 1;
        await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('p3')));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(find.text('Unable to render PDF'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(find.text('Unable to render PDF'), findsNothing);
        expect(find.byType(Image), findsOneWidget);
        expect(platform.opened, hasLength(2));
      },
    );

    testWidgets('a repeated open failure keeps showing the error', (
      tester,
    ) async {
      platform.failOpens = 2;
      await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('p4')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Unable to render PDF'), findsOneWidget);
    });

    testWidgets('a page render failure shows a page-level error and Retry '
        're-renders only that page', (tester) async {
      platform.failRenders = 1;
      await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('p5')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Unable to render this page'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Unable to render this page'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('swiping saves the page and a later mount resumes there', (
      tester,
    ) async {
      final memory = InMemoryPdfPageMemory();
      final renderer = PdfAttachmentRenderer(pageMemory: memory);
      await tester.pumpWidget(host(renderer, _pdf('resume')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(memory.lastPage('resume'), 1);

      await tester.pumpWidget(const SizedBox());
      platform.rendered.clear();
      await tester.pumpWidget(host(renderer, _pdf('resume')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(platform.rendered, contains(1));
      expect(platform.rendered, isNot(contains(0)));
    });

    testWidgets(
      'a remembered page beyond the page count falls back to page 0',
      (tester) async {
        final memory = InMemoryPdfPageMemory()..savePage('stale', 99);
        platform.pages = 2;
        await tester.pumpWidget(
          host(PdfAttachmentRenderer(pageMemory: memory), _pdf('stale')),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(platform.rendered.first, 0);
      },
    );

    testWidgets(
      'a remembered page exactly equal to the page count is out of range',
      (tester) async {
        final memory = InMemoryPdfPageMemory()..savePage('edge', 2);
        platform.pages = 2;
        await tester.pumpWidget(
          host(PdfAttachmentRenderer(pageMemory: memory), _pdf('edge')),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(platform.rendered.first, 0);
      },
    );

    testWidgets('a single-page document has nothing to swipe to', (
      tester,
    ) async {
      platform.pages = 1;
      await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('single')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
      'a zero-page document renders an empty pager without throwing',
      (tester) async {
        platform.pages = 0;
        await tester.pumpWidget(host(PdfAttachmentRenderer(), _pdf('zero')));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets('disposing closes the native document', (tester) async {
      await tester.pumpWidget(
        host(PdfAttachmentRenderer(), _pdf('d1', path: '/tmp/close.pdf')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(platform.closed, ['/tmp/close.pdf']);
    });

    testWidgets(
      'disposing before the open resolves still closes the late document',
      (tester) async {
        await tester.pumpWidget(
          host(PdfAttachmentRenderer(), _pdf('d2', path: '/tmp/late.pdf')),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pump();
        expect(platform.closed, ['/tmp/late.pdf']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders in RTL, dark mode and a small screen', (tester) async {
      setScreenSize(tester, const Size(120, 160));
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (c) => PdfAttachmentRenderer().build(c, _pdf('rtl')),
          ),
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });
}
