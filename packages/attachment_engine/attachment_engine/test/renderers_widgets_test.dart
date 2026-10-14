// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/renderers/renderer_error_state.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'helpers/fake_webview.dart';
import 'helpers/widget_harness.dart';
import 'helpers/zip_builder.dart';

class _Platform extends AttachmentEnginePlatform {
  _Platform(this.supportDir);

  final String supportDir;
  final List<String> opened = [];
  NativeOpenResult openResult = const NativeOpenResult(success: true);

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    opened.add(path);
    return openResult;
  }

  @override
  Future<String> getApplicationSupportDirectory() async => supportDir;
}

Attachment _att(
  AttachmentType type, {
  String id = 'a1',
  String name = 'Doc',
  String? localPath,
  String? remoteUrl,
  AttachmentSource source = const AttachmentSource.url('https://e.com/f'),
}) => Attachment(
  id: id,
  name: name,
  source: source,
  attachmentType: type,
  localPath: localPath,
  remoteUrl: remoteUrl,
);

/// Lets real file I/O finish (bounded number of 1 ms real-async turns).
Future<void> settle(WidgetTester tester, {int turns = 60}) async {
  for (var i = 0; i < turns; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
  }
}

void main() {
  late Directory tempDir;
  late _Platform platform;
  late FakeWebViewPlatform webview;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('renderers_widgets_test');
    platform = _Platform('${tempDir.path}/support');
    AttachmentEnginePlatform.instance = platform;
    NativePathsChannel.resetForTesting();
    webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
  });

  tearDown(() {
    NativePathsChannel.resetForTesting();
    tempDir.deleteSync(recursive: true);
  });

  group('RendererErrorState', () {
    testWidgets('shows the message and default icon without a retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(const RendererErrorState(message: 'Broken')),
      );
      expect(find.text('Broken'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('custom icon and a working retry button', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        harness(
          RendererErrorState(
            message: 'x',
            icon: Icons.broken_image_outlined,
            onRetry: () => retries++,
          ),
        ),
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      expect(retries, 2);
    });

    testWidgets('icon chip is tinted from the theme error colour in light '
        'and dark mode', (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(
          harness(const RendererErrorState(message: 'x'), brightness: b),
        );
        final scheme = Theme.of(tester.element(find.byType(RendererErrorState)))
            .colorScheme;
        expect(tester.widget<Icon>(find.byType(Icon)).color, scheme.error);
        final box = tester.widget<Container>(find.byType(Container).first);
        expect(
          (box.decoration! as BoxDecoration).color,
          scheme.error.withValues(alpha: 0.1),
        );
      }
    });

    testWidgets('empty message, RTL and large text render without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          RendererErrorState(message: '', onRetry: () {}),
          textDirection: TextDirection.rtl,
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long message wraps on a narrow screen', (tester) async {
      setScreenSize(tester, const Size(200, 600));
      await tester.pumpWidget(
        harness(RendererErrorState(message: 'word ' * 6, onRetry: () {})),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('UnknownAttachmentRenderer', () {
    Widget host(UnknownAttachmentRenderer r, Attachment a) =>
        harness(Builder(builder: (context) => r.build(context, a)));

    test('reports the unknown type', () {
      expect(const UnknownAttachmentRenderer().type, AttachmentType.unknown);
    });

    testWidgets('offers "Open externally" for a local file and opens it', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const UnknownAttachmentRenderer(),
          _att(AttachmentType.unknown, localPath: '/data/file.bin'),
        ),
      );
      expect(find.text('Doc'), findsOneWidget);
      await tester.tap(find.text('Open externally'));
      await tester.pump();
      expect(platform.opened, ['/data/file.bin']);
    });

    testWidgets('a failed external open does not throw', (tester) async {
      platform.openResult = const NativeOpenResult(
        success: false,
        message: 'no app',
      );
      await tester.pumpWidget(
        host(
          const UnknownAttachmentRenderer(),
          _att(AttachmentType.unknown, localPath: '/data/file.bin'),
        ),
      );
      await tester.tap(find.text('Open externally'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no local path: only the name, no affordance', (tester) async {
      await tester.pumpWidget(
        host(const UnknownAttachmentRenderer(), _att(AttachmentType.unknown)),
      );
      expect(find.text('Doc'), findsOneWidget);
      expect(find.text('Open externally'), findsNothing);
    });

    testWidgets('external fallback disallowed: shows "not supported"', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const UnknownAttachmentRenderer(
            externalOpenConfig: ExternalOpenConfig(
              allowExternalFallback: false,
            ),
          ),
          _att(AttachmentType.unknown, localPath: '/data/file.bin'),
        ),
      );
      expect(
        find.text('This attachment type is not supported.'),
        findsOneWidget,
      );
      expect(find.text('Open externally'), findsNothing);
    });

    testWidgets('disabled by config and external fallback disallowed: shows '
        'the disabled message', (tester) async {
      await tester.pumpWidget(
        host(
          const UnknownAttachmentRenderer(
            externalOpenConfig: ExternalOpenConfig(
              allowExternalFallback: false,
            ),
            disabledByConfig: true,
          ),
          _att(AttachmentType.pdf, localPath: '/data/file.pdf'),
        ),
      );
      expect(
        find.text('Viewing this attachment type has been disabled.'),
        findsOneWidget,
      );
    });

    testWidgets('disabled by config with external fallback allowed still '
        'offers external open', (tester) async {
      await tester.pumpWidget(
        host(
          const UnknownAttachmentRenderer(disabledByConfig: true),
          _att(AttachmentType.pdf, localPath: '/data/file.pdf'),
        ),
      );
      expect(find.text('Open externally'), findsOneWidget);
    });

    testWidgets('long name, RTL, dark and large text render without errors', (
      tester,
    ) async {
      setScreenSize(tester, const Size(240, 400));
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => const UnknownAttachmentRenderer().build(
              context,
              _att(AttachmentType.unknown, name: 'n' * 40, localPath: '/x'),
            ),
          ),
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('RendererRegistry', () {
    test('default registry maps every built-in type to its renderer', () {
      final registry = RendererRegistry();
      expect(
        registry.rendererFor(AttachmentType.image),
        isA<ImageAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.pdf),
        isA<PdfAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.video),
        isA<VideoAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.audio),
        isA<AudioAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.html),
        isA<HtmlAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.csv),
        isA<CsvAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.text),
        isA<TextAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.scorm),
        isA<ScormAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.office),
        isA<OfficeAttachmentRenderer>(),
      );
      expect(
        registry.rendererFor(AttachmentType.archive),
        isA<ArchiveAttachmentRenderer>(),
      );
    });

    test('types with no registered renderer fall back to unknown', () {
      final registry = RendererRegistry();
      for (final t in [
        AttachmentType.unknown,
        AttachmentType.document,
        AttachmentType.h5p,
      ]) {
        final r = registry.rendererFor(t);
        expect(r, isA<UnknownAttachmentRenderer>());
        expect((r as UnknownAttachmentRenderer).disabledByConfig, isFalse);
      }
    });

    test('a disabled type yields an unknown renderer flagged as disabled and '
        'carries the external-open config', () {
      final registry = RendererRegistry(
        rendererConfig: const RendererConfig(pdf: false),
        externalOpenConfig: const ExternalOpenConfig(
          allowExternalFallback: false,
        ),
      );
      final r =
          registry.rendererFor(AttachmentType.pdf) as UnknownAttachmentRenderer;
      expect(r.disabledByConfig, isTrue);
      expect(r.externalOpenConfig.allowExternalFallback, isFalse);
      expect(
        registry.rendererFor(AttachmentType.image),
        isA<ImageAttachmentRenderer>(),
      );
    });

    test('register() replaces the renderer for its type', () {
      final registry = RendererRegistry(renderers: const []);
      const custom = _CustomRenderer();
      registry.register(custom);
      expect(registry.rendererFor(AttachmentType.pdf), same(custom));
      const replacement = _CustomRenderer();
      registry.register(replacement);
      expect(registry.rendererFor(AttachmentType.pdf), same(replacement));
    });

    test('an explicit empty renderer list means no built-ins', () {
      expect(
        RendererRegistry(renderers: const []).rendererFor(AttachmentType.image),
        isA<UnknownAttachmentRenderer>(),
      );
    });

    test('a custom renderer registered for unknown is used even when '
        'rendererConfig disables nothing', () {
      final registry = RendererRegistry(renderers: const [_UnknownCustom()]);
      expect(
        registry.rendererFor(AttachmentType.unknown),
        isA<_UnknownCustom>(),
      );
    });

    testWidgets('build() dispatches on the attachment type', (tester) async {
      final registry = RendererRegistry(renderers: const [_CustomRenderer()]);
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => registry.build(
              context,
              _att(AttachmentType.pdf, name: 'pdf-one'),
            ),
          ),
        ),
      );
      expect(find.text('custom:pdf-one'), findsOneWidget);
    });
  });

  group('ImageAttachmentRenderer', () {
    const renderer = ImageAttachmentRenderer();

    Widget host(Attachment a, {TextDirection dir = TextDirection.ltr}) =>
        harness(
          Builder(builder: (context) => renderer.build(context, a)),
          textDirection: dir,
        );

    test('type is image', () => expect(renderer.type, AttachmentType.image));

    testWidgets('no path or url shows the unavailable state', (tester) async {
      await tester.pumpWidget(
        host(
          _att(
            AttachmentType.image,
            source: const AttachmentSource.file('/not/used'),
          ),
        ),
      );
      expect(find.text('Image unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('a cache-source attachment with no path is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(_att(AttachmentType.image, source: AttachmentSource.cache('k'))),
      );
      expect(find.text('Image unavailable'), findsOneWidget);
    });

    testWidgets('a local file renders inside a zoomable InteractiveViewer', (
      tester,
    ) async {
      final file = File('${tempDir.path}/p.png')..writeAsBytesSync(kTinyPng);
      await tester.pumpWidget(
        host(_att(AttachmentType.image, localPath: file.path)),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 0.1);
      expect(viewer.maxScale, 5);
      expect(viewer.boundaryMargin, const EdgeInsets.all(double.infinity));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('pinch-to-zoom scales the content', (tester) async {
      final file = File('${tempDir.path}/p.png')..writeAsBytesSync(kTinyPng);
      await tester.pumpWidget(
        host(_att(AttachmentType.image, localPath: file.path)),
      );
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final g1 = await tester.startGesture(center - const Offset(20, 0));
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Transform),
        ),
      );
      expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));
    });

    testWidgets('a remote url uses a network image', (tester) async {
      await tester.pumpWidget(
        host(_att(AttachmentType.image, remoteUrl: 'https://e.com/i.png')),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<NetworkImage>(),
      );
      await tester.pumpWidget(const SizedBox());
      tester.takeException();
    });

    testWidgets('falls back to a url source when remoteUrl is unset', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          _att(
            AttachmentType.image,
            source: const AttachmentSource.url('https://e.com/from-source.png'),
          ),
        ),
      );
      expect(
        (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
        'https://e.com/from-source.png',
      );
      await tester.pumpWidget(const SizedBox());
      tester.takeException();
    });

    testWidgets('a corrupt image file shows the unavailable state via the '
        'error builder', (tester) async {
      final file = File('${tempDir.path}/bad.png')
        ..writeAsBytesSync(utf8.encode('definitely not a png'));
      await tester.pumpWidget(
        host(_att(AttachmentType.image, localPath: file.path)),
      );
      await pumpUntilFound(tester, find.text('Image unavailable'));
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('a missing image file shows the unavailable state', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(_att(AttachmentType.image, localPath: '${tempDir.path}/nope.png')),
      );
      await pumpUntilFound(tester, find.text('Image unavailable'));
    });

    testWidgets('renders in RTL', (tester) async {
      final file = File('${tempDir.path}/p.png')..writeAsBytesSync(kTinyPng);
      await tester.pumpWidget(
        host(
          _att(AttachmentType.image, localPath: file.path),
          dir: TextDirection.rtl,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('HtmlAttachmentRenderer', () {
    const renderer = HtmlAttachmentRenderer();

    Widget host(Attachment a) =>
        harness(Builder(builder: (context) => renderer.build(context, a)));

    test('type is html', () => expect(renderer.type, AttachmentType.html));

    testWidgets('loads a local file with JavaScript enabled', (tester) async {
      await tester.pumpWidget(
        host(_att(AttachmentType.html, localPath: '/data/index.html')),
      );
      final c = webview.controllers.single;
      expect(c.loadedFiles, ['/data/index.html']);
      expect(c.loadedRequests, isEmpty);
      expect(c.javaScriptMode, JavaScriptMode.unrestricted);
    });

    testWidgets('a local path wins over a remote url', (tester) async {
      await tester.pumpWidget(
        host(
          _att(
            AttachmentType.html,
            localPath: '/data/index.html',
            remoteUrl: 'https://e.com/x.html',
          ),
        ),
      );
      expect(webview.controllers.single.loadedFiles, ['/data/index.html']);
      expect(webview.controllers.single.loadedRequests, isEmpty);
    });

    testWidgets('loads a remote url when there is no local file', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(_att(AttachmentType.html, remoteUrl: 'https://e.com/x.html?a=1')),
      );
      expect(webview.controllers.single.loadedRequests, [
        Uri.parse('https://e.com/x.html?a=1'),
      ]);
    });

    testWidgets('with neither path nor url nothing is loaded', (tester) async {
      await tester.pumpWidget(host(_att(AttachmentType.html)));
      final c = webview.controllers.single;
      expect(c.loadedFiles, isEmpty);
      expect(c.loadedRequests, isEmpty);
      expect(find.byType(WebViewWidget), findsOneWidget);
    });

    testWidgets('rebuilding does not recreate the controller', (tester) async {
      final a = _att(AttachmentType.html, localPath: '/data/index.html');
      await tester.pumpWidget(host(a));
      await tester.pumpWidget(host(a));
      expect(webview.controllers, hasLength(1));
    });
  });

  group('ArchiveAttachmentRenderer', () {
    const renderer = ArchiveAttachmentRenderer();

    Widget host(Attachment a) =>
        harness(Builder(builder: (context) => renderer.build(context, a)));

    test(
      'type is archive',
      () => expect(renderer.type, AttachmentType.archive),
    );

    testWidgets('no local path shows the unavailable state', (tester) async {
      await tester.pumpWidget(host(_att(AttachmentType.archive)));
      expect(find.text('Archive unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.folder_zip_outlined), findsOneWidget);
    });

    testWidgets('lists the names of every entry', (tester) async {
      final zip = File('${tempDir.path}/a.zip')
        ..writeAsBytesSync(
          buildZip([
            const TestZipEntry('docs/', []),
            const TestZipEntry('docs/readme.txt', [1, 2, 3]),
            const TestZipEntry('image.png', [4]),
          ]),
        );
      await tester.pumpWidget(
        host(_att(AttachmentType.archive, localPath: zip.path)),
      );
      await pumpUntilFound(tester, find.text('image.png'));
      expect(find.text('docs/'), findsOneWidget);
      expect(find.text('docs/readme.txt'), findsOneWidget);
    });

    testWidgets('an empty archive renders an empty list', (tester) async {
      final zip = File('${tempDir.path}/empty.zip')
        ..writeAsBytesSync(buildZip([]));
      await tester.pumpWidget(
        host(_att(AttachmentType.archive, localPath: zip.path)),
      );
      await pumpUntil(
        tester,
        () => find.byType(ListView).evaluate().isNotEmpty,
        reason: 'list view',
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a large archive is built lazily and scrolls', (tester) async {
      setScreenSize(tester, const Size(300, 400));
      final zip = File('${tempDir.path}/big.zip')
        ..writeAsBytesSync(
          buildZip([
            for (var i = 0; i < 500; i++) TestZipEntry('f$i.txt', [i % 256]),
          ]),
        );
      await tester.pumpWidget(
        host(_att(AttachmentType.archive, localPath: zip.path)),
      );
      await pumpUntilFound(tester, find.text('f0.txt'));
      expect(find.byType(Text).evaluate().length, lessThan(60));
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('f0.txt'), findsNothing);
    });

    testWidgets('a corrupt or missing archive never throws and shows the '
        'placeholder', (tester) async {
      final bad = File('${tempDir.path}/bad.zip')
        ..writeAsBytesSync([1, 2, 3, 4]);
      await tester.pumpWidget(
        host(_att(AttachmentType.archive, localPath: bad.path)),
      );
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsNothing);
    });
  });

  group('ScormAttachmentRenderer', () {
    const renderer = ScormAttachmentRenderer();

    Widget host(Attachment a) =>
        harness(Builder(builder: (context) => renderer.build(context, a)));

    File writeZip(String name, List<TestZipEntry> entries) =>
        File('${tempDir.path}/$name')..writeAsBytesSync(buildZip(entries));

    List<TestZipEntry> pkg(List<String> htmlNames) => [
      const TestZipEntry('imsmanifest.xml', [60, 47, 62]),
      for (final n in htmlNames) TestZipEntry(n, utf8.encode('<html/>')),
    ];

    test('type is scorm', () => expect(renderer.type, AttachmentType.scorm));

    testWidgets(
      'a package that cannot be launched falls back to the unknown-file view',
      (tester) async {
        final broken = File('${tempDir.path}/broken.zip')
          ..writeAsBytesSync([1, 2, 3, 4]);
        await tester.pumpWidget(
          host(
            _att(
              AttachmentType.scorm,
              id: 'bad',
              name: 'Broken course',
              localPath: broken.path,
            ),
          ),
        );
        await pumpUntilFound(tester, find.text('Broken course'));
        expect(find.byType(SizedBox), findsWidgets);
      },
    );

    testWidgets(
      'a package without a local file falls back to the unknown-file view',
      (tester) async {
        await tester.pumpWidget(
          host(_att(AttachmentType.scorm, id: 'remote', name: 'Remote course')),
        );
        await pumpUntilFound(tester, find.text('Remote course'));
      },
    );

    testWidgets('shows a placeholder while preparing, then loads the entry '
        'page in the web view', (tester) async {
      final zip = writeZip('p.zip', pkg(['content/index.html']));
      await tester.pumpWidget(
        host(_att(AttachmentType.scorm, id: 'pkg1', localPath: zip.path)),
      );
      expect(find.byType(WebViewWidget), findsNothing);
      await pumpUntilFound(tester, find.byType(WebViewWidget));
      final loaded = webview.controllers.single.loadedFiles.single;
      expect(loaded, endsWith('scorm_pkg1/content/index.html'));
      expect(File(loaded).existsSync(), isTrue);
    });

    testWidgets('prefers index.html, then index_lms.html, then any html', (
      tester,
    ) async {
      final cases = <String, (List<String>, String)>{
        'a': (['z.html', 'sub/index.html'], 'index.html'),
        'b': (['z.html', 'INDEX_LMS.HTML'], 'INDEX_LMS.HTML'),
        'c': (['only.html', 'asset.js'], 'only.html'),
      };
      for (final entry in cases.entries) {
        webview.controllers.clear();
        final zip = writeZip('${entry.key}.zip', pkg(entry.value.$1));
        await tester.pumpWidget(
          host(_att(AttachmentType.scorm, id: entry.key, localPath: zip.path)),
        );
        await pumpUntilFound(tester, find.byType(WebViewWidget));
        expect(
          webview.controllers.single.loadedFiles.single,
          endsWith(entry.value.$2),
          reason: entry.key,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('no local path never loads a web view', (tester) async {
      await tester.pumpWidget(host(_att(AttachmentType.scorm)));
      await settle(tester);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(webview.controllers, isEmpty);
    });

    testWidgets('a zip without imsmanifest.xml is not a SCORM package', (
      tester,
    ) async {
      final zip = writeZip('n.zip', [
        const TestZipEntry('index.html', [1]),
      ]);
      await tester.pumpWidget(
        host(_att(AttachmentType.scorm, localPath: zip.path)),
      );
      await settle(tester);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(webview.controllers, isEmpty);
    });

    testWidgets('a manifest with no html entry never loads a web view', (
      tester,
    ) async {
      final zip = writeZip('m.zip', pkg(['data.js']));
      await tester.pumpWidget(
        host(_att(AttachmentType.scorm, localPath: zip.path)),
      );
      await settle(tester);
      expect(webview.controllers, isEmpty);
    });

    testWidgets('a corrupt or missing package never throws or loads a web '
        'view', (tester) async {
      final bad = File('${tempDir.path}/bad.zip')..writeAsBytesSync([9, 9, 9]);
      await tester.pumpWidget(
        host(_att(AttachmentType.scorm, localPath: bad.path)),
      );
      await settle(tester);

      await tester.pumpWidget(
        host(
          _att(
            AttachmentType.scorm,
            id: 'x',
            localPath: '${tempDir.path}/gone.zip',
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(webview.controllers, isEmpty);
    });

    testWidgets('malicious entries are skipped during extraction', (
      tester,
    ) async {
      final zip = writeZip('evil.zip', [
        ...pkg(['index.html']),
        const TestZipEntry('../escape.html', [1]),
      ]);
      await tester.pumpWidget(
        host(_att(AttachmentType.scorm, id: 'evil', localPath: zip.path)),
      );
      await pumpUntilFound(tester, find.byType(WebViewWidget));
      expect(File('${tempDir.path}/support/escape.html').existsSync(), isFalse);
      expect(File('${tempDir.path}/escape.html').existsSync(), isFalse);
    });

    testWidgets('disposing while preparing is safe', (tester) async {
      final zip = writeZip('d.zip', pkg(['index.html']));
      await tester.pumpWidget(
        host(_att(AttachmentType.scorm, id: 'd', localPath: zip.path)),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('archive helpers', () {
    test('archiveContainsScormManifest detects the manifest case-insensitively '
        'in nested folders', () async {
      final yes = File('${tempDir.path}/y.zip')
        ..writeAsBytesSync(
          buildZip([
            const TestZipEntry('pkg/IMSMANIFEST.XML', [1]),
          ]),
        );
      final no = File('${tempDir.path}/n.zip')
        ..writeAsBytesSync(
          buildZip([
            const TestZipEntry('manifest.xml', [1]),
          ]),
        );
      expect(await archiveContainsScormManifest(yes), isTrue);
      expect(await archiveContainsScormManifest(no), isFalse);
    });

    test('extractArchiveSafely writes files and directories, skips symlinks '
        'and traversal, and supports deflate', () async {
      final zip = File('${tempDir.path}/x.zip')
        ..writeAsBytesSync(
          buildZip([
            const TestZipEntry('dir/', []),
            TestZipEntry(
              'dir/a.txt',
              utf8.encode('hello hello hello hello'),
              deflate: true,
            ),
            const TestZipEntry('link', [1], symlink: true),
            const TestZipEntry('..\\evil', [1]),
            const TestZipEntry(r'\abs', [1]),
            const TestZipEntry('/abs2', [1]),
          ]),
        );
      final target = Directory('${tempDir.path}/out');
      final extracted = await extractArchiveSafely(zip, target);
      expect(extracted, hasLength(1));
      expect(
        File(extracted.single).readAsStringSync(),
        'hello hello hello hello',
      );
      expect(Directory('${target.path}/dir').existsSync(), isTrue);
      expect(File('${target.path}/link').existsSync(), isFalse);
    });

    test('extractArchiveSafely propagates a corrupt-archive error', () async {
      final zip = File('${tempDir.path}/bad.zip')..writeAsBytesSync([1, 2, 3]);
      await expectLater(
        extractArchiveSafely(zip, Directory('${tempDir.path}/o')),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

class _CustomRenderer extends AttachmentRenderer {
  const _CustomRenderer();

  @override
  AttachmentType get type => AttachmentType.pdf;

  @override
  Widget build(BuildContext context, Attachment attachment) =>
      Text('custom:${attachment.name}');
}

class _UnknownCustom extends AttachmentRenderer {
  const _UnknownCustom();

  @override
  AttachmentType get type => AttachmentType.unknown;

  @override
  Widget build(BuildContext context, Attachment attachment) => const SizedBox();
}
