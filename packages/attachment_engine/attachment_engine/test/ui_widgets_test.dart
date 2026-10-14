// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/widget_harness.dart';

Attachment _att(
  String id, {
  AttachmentType type = AttachmentType.pdf,
  String? localPath,
  String? remoteUrl,
  String? name,
}) => Attachment(
  id: id,
  name: name ?? 'file-$id',
  source: AttachmentSource.url('https://example.com/$id'),
  attachmentType: type,
  localPath: localPath,
  remoteUrl: remoteUrl,
);

void main() {
  late Directory tempDir;

  late String png;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ui_widgets_test');
    png = (File('${tempDir.path}/shared.png')..writeAsBytesSync(kTinyPng)).path;
  });

  // Grid cells are built with `size: double.infinity`, which only works for
  // image thumbnails (an Icon cannot take an infinite size), so the grid
  // tests use local images.
  Attachment img(String id) =>
      _att(id, type: AttachmentType.image, localPath: png);

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('AttachmentActions', () {
    const all = AttachmentCapabilities(
      canShare: true,
      canDownload: true,
      canOpenExternally: true,
      canDeleteCache: true,
    );

    testWidgets('renders and fires all four actions when everything is '
        'available', (tester) async {
      final fired = <String>[];
      await tester.pumpWidget(
        harness(
          AttachmentActions(
            capabilities: all,
            onShare: () => fired.add('share'),
            onDownload: () => fired.add('download'),
            onOpenExternally: () => fired.add('open'),
            onDeleteCache: () => fired.add('delete'),
          ),
        ),
      );

      expect(find.byType(IconButton), findsNWidgets(4));
      await tester.tap(find.byIcon(Icons.share));
      await tester.tap(find.byIcon(Icons.download));
      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.tap(find.byIcon(Icons.delete_outline));
      expect(fired, ['share', 'download', 'open', 'delete']);
    });

    testWidgets('omits every action when capabilities are none', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentActions(
            capabilities: AttachmentCapabilities.none,
            onShare: () {},
            onDownload: () {},
            onOpenExternally: () {},
            onDeleteCache: () {},
          ),
        ),
      );
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('omits actions whose callback is null even if capable', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(const AttachmentActions(capabilities: all)),
      );
      expect(find.byType(IconButton), findsNothing);
    });

    for (final c in <String, (AttachmentCapabilities, IconData)>{
      'share': (const AttachmentCapabilities(canShare: true), Icons.share),
      'download': (
        const AttachmentCapabilities(canDownload: true),
        Icons.download,
      ),
      'open': (
        const AttachmentCapabilities(canOpenExternally: true),
        Icons.open_in_new,
      ),
      'delete': (
        const AttachmentCapabilities(canDeleteCache: true),
        Icons.delete_outline,
      ),
    }.entries) {
      testWidgets('only the ${c.key} action shows when only it is '
          'capable (others have callbacks but no capability)', (tester) async {
        await tester.pumpWidget(
          harness(
            AttachmentActions(
              capabilities: c.value.$1,
              onShare: () {},
              onDownload: () {},
              onOpenExternally: () {},
              onDeleteCache: () {},
            ),
          ),
        );
        expect(find.byType(IconButton), findsOneWidget);
        expect(find.byIcon(c.value.$2), findsOneWidget);
      });
    }

    testWidgets('RTL mirrors the order of the buttons', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentActions(
            capabilities: all,
            onShare: () {},
            onDownload: () {},
            onOpenExternally: () {},
            onDeleteCache: () {},
          ),
          textDirection: TextDirection.rtl,
        ),
      );
      final shareX = tester.getCenter(find.byIcon(Icons.share)).dx;
      final deleteX = tester.getCenter(find.byIcon(Icons.delete_outline)).dx;
      expect(shareX, greaterThan(deleteX));
    });

    testWidgets('renders in dark mode with a large text scale', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentActions(
            capabilities: all,
            onShare: () {},
            onDownload: () {},
            onOpenExternally: () {},
            onDeleteCache: () {},
          ),
          brightness: Brightness.dark,
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(IconButton), findsNWidgets(4));
    });

    testWidgets('re-render with changed capabilities updates the buttons', (
      tester,
    ) async {
      Widget build(AttachmentCapabilities caps) =>
          harness(AttachmentActions(capabilities: caps, onShare: () {}));
      await tester.pumpWidget(
        build(const AttachmentCapabilities(canShare: true)),
      );
      expect(find.byIcon(Icons.share), findsOneWidget);
      await tester.pumpWidget(build(AttachmentCapabilities.none));
      expect(find.byIcon(Icons.share), findsNothing);
    });
  });

  group('AttachmentDownloadProgress', () {
    Future<StreamController<DownloadProgress>> pumpProgress(
      WidgetTester tester,
    ) async {
      final controller = StreamController<DownloadProgress>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(
        harness(AttachmentDownloadProgress(stream: controller.stream)),
      );
      return controller;
    }

    double? value(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;

    testWidgets('is indeterminate before any event arrives', (tester) async {
      await pumpProgress(tester);
      expect(value(tester), isNull);
      // Indeterminate indicators animate forever; dispose explicitly.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the fraction of each progress event', (tester) async {
      final c = await pumpProgress(tester);
      c.add(const DownloadProgress(received: 25, total: 100));
      await tester.idle();
      await tester.pump();
      expect(value(tester), 0.25);
      c.add(const DownloadProgress(received: 100, total: 100));
      await tester.idle();
      await tester.pump();
      expect(value(tester), 1.0);
      c.add(const DownloadProgress(received: 0, total: 100));
      await tester.idle();
      await tester.pump();
      expect(value(tester), 0.0);
    });

    testWidgets('stays indeterminate when total is unknown or zero', (
      tester,
    ) async {
      final c = await pumpProgress(tester);
      c.add(const DownloadProgress(received: 50, total: null));
      await tester.idle();
      await tester.pump();
      expect(value(tester), isNull);
      c.add(const DownloadProgress(received: 50, total: 0));
      await tester.idle();
      await tester.pump();
      expect(value(tester), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a stream error does not crash and keeps the last state', (
      tester,
    ) async {
      final c = await pumpProgress(tester);
      c.add(const DownloadProgress(received: 1, total: 4));
      await tester.idle();
      await tester.pump();
      c.addError(StateError('boom'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('swapping the stream follows the new stream', (tester) async {
      final a = StreamController<DownloadProgress>.broadcast();
      final b = StreamController<DownloadProgress>.broadcast();
      addTearDown(a.close);
      addTearDown(b.close);
      await tester.pumpWidget(
        harness(AttachmentDownloadProgress(stream: a.stream)),
      );
      a.add(const DownloadProgress(received: 1, total: 2));
      await tester.idle();
      await tester.pump();
      expect(value(tester), 0.5);
      await tester.pumpWidget(
        harness(AttachmentDownloadProgress(stream: b.stream)),
      );
      b.add(const DownloadProgress(received: 3, total: 4));
      await tester.idle();
      await tester.pump();
      expect(value(tester), 0.75);
    });

    testWidgets('disposing mid-stream and emitting afterwards is safe', (
      tester,
    ) async {
      final c = await pumpProgress(tester);
      await tester.pumpWidget(const SizedBox());
      c.add(const DownloadProgress(received: 1, total: 2));
      await tester.idle();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a done stream retains the final value', (tester) async {
      final c = StreamController<DownloadProgress>();
      await tester.pumpWidget(
        harness(AttachmentDownloadProgress(stream: c.stream)),
      );
      c.add(const DownloadProgress(received: 9, total: 10));
      await c.close();
      await tester.pump();
      expect(value(tester), 0.9);
    });

    testWidgets('renders in RTL and dark mode', (tester) async {
      final c = StreamController<DownloadProgress>.broadcast();
      addTearDown(c.close);
      await tester.pumpWidget(
        harness(
          AttachmentDownloadProgress(stream: c.stream),
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
        ),
      );
      c.add(const DownloadProgress(received: 1, total: 2));
      await tester.idle();
      await tester.pump();
      expect(value(tester), 0.5);
    });

    testWidgets('over-reported progress (received > total) does not throw', (
      tester,
    ) async {
      final c = await pumpProgress(tester);
      c.add(const DownloadProgress(received: 150, total: 100));
      await tester.idle();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('DownloadProgress', () {
    test('fraction is null for unknown/zero totals and exact otherwise', () {
      expect(const DownloadProgress(received: 1, total: null).fraction, isNull);
      expect(const DownloadProgress(received: 1, total: 0).fraction, isNull);
      expect(const DownloadProgress(received: 0, total: 10).fraction, 0.0);
      expect(const DownloadProgress(received: 5, total: 10).fraction, 0.5);
      expect(const DownloadProgress(received: 10, total: 10).fraction, 1.0);
    });
  });

  group('AttachmentThumbnail', () {
    const expectedIcons = <AttachmentType, IconData>{
      AttachmentType.image: Icons.image,
      AttachmentType.pdf: Icons.picture_as_pdf,
      AttachmentType.document: Icons.description,
      AttachmentType.office: Icons.description,
      AttachmentType.text: Icons.article,
      AttachmentType.csv: Icons.table_chart,
      AttachmentType.html: Icons.public,
      AttachmentType.scorm: Icons.school,
      AttachmentType.h5p: Icons.school,
      AttachmentType.video: Icons.movie,
      AttachmentType.audio: Icons.audiotrack,
      AttachmentType.archive: Icons.folder_zip,
      AttachmentType.unknown: Icons.insert_drive_file,
    };

    test('the table covers every AttachmentType', () {
      expect(expectedIcons.keys.toSet(), AttachmentType.values.toSet());
    });

    for (final entry in expectedIcons.entries) {
      testWidgets('${entry.key.name} shows its type icon', (tester) async {
        await tester.pumpWidget(
          harness(AttachmentThumbnail(attachment: _att('t', type: entry.key))),
        );
        expect(find.byIcon(entry.value), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      });
    }

    testWidgets('size drives both the box and the icon (60%)', (tester) async {
      await tester.pumpWidget(
        harness(AttachmentThumbnail(attachment: _att('t'), size: 100)),
      );
      expect(
        tester.getSize(find.byType(AttachmentThumbnail)),
        const Size(100, 100),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).size, 60);
    });

    testWidgets('default size is 48', (tester) async {
      await tester.pumpWidget(
        harness(AttachmentThumbnail(attachment: _att('t'))),
      );
      expect(
        tester.getSize(find.byType(AttachmentThumbnail)),
        const Size(48, 48),
      );
    });

    testWidgets('zero size renders without error', (tester) async {
      await tester.pumpWidget(
        harness(AttachmentThumbnail(attachment: _att('t'), size: 0)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an image with a local path renders a clipped Image.file', (
      tester,
    ) async {
      final file = File('${tempDir.path}/p.png')..writeAsBytesSync(kTinyPng);
      await tester.pumpWidget(
        harness(
          AttachmentThumbnail(
            attachment: _att(
              't',
              type: AttachmentType.image,
              localPath: file.path,
            ),
            size: 32,
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 32);
      expect(image.height, 32);
      expect(image.fit, BoxFit.cover);
      expect((image.image as FileImage).file.path, file.path);
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(6));
    });

    testWidgets('an image without a local path falls back to its icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentThumbnail(
            attachment: _att(
              't',
              type: AttachmentType.image,
              remoteUrl: 'https://x',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a non-image type ignores localPath and shows its icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentThumbnail(
            attachment: _att(
              't',
              type: AttachmentType.pdf,
              localPath: '/x.png',
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });
  });

  group('AttachmentPreview', () {
    testWidgets('local image renders Image.file with cover fit', (
      tester,
    ) async {
      final file = File('${tempDir.path}/p.png')..writeAsBytesSync(kTinyPng);
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              'i',
              type: AttachmentType.image,
              localPath: file.path,
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('local path wins over a remote url for images', (tester) async {
      final file = File('${tempDir.path}/p.png')..writeAsBytesSync(kTinyPng);
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              'i',
              type: AttachmentType.image,
              localPath: file.path,
              remoteUrl: 'https://example.com/i.png',
            ),
          ),
        ),
      );
      expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
    });

    testWidgets('remote-only image uses a network image provider', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              'i',
              type: AttachmentType.image,
              remoteUrl: 'https://example.com/i.png',
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url, 'https://example.com/i.png');
      expect(image.fit, BoxFit.cover);
      // Consume the (mocked, failing) load so it cannot surface after the test.
      await tester.pumpWidget(const SizedBox());
      tester.takeException();
    });

    testWidgets('an image with no path or url falls back to a thumbnail', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentPreview(attachment: _att('i', type: AttachmentType.image)),
        ),
      );
      expect(find.byType(AttachmentThumbnail), findsOneWidget);
      expect(find.byIcon(Icons.image), findsOneWidget);
    });

    testWidgets('non-image, non-text types show a 64px thumbnail', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentPreview(attachment: _att('p', type: AttachmentType.pdf)),
        ),
      );
      expect(
        tester
            .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
            .size,
        64,
      );
      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });

    testWidgets('text without a local path renders an empty Text', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentPreview(attachment: _att('t', type: AttachmentType.text)),
        ),
      );
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('short text file shows its content in full', (tester) async {
      final file = File('${tempDir.path}/a.txt')
        ..writeAsStringSync('hello snippet');
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              't',
              type: AttachmentType.text,
              localPath: file.path,
            ),
          ),
        ),
      );
      await pumpUntilFound(tester, find.text('hello snippet'));
      final text = tester.widget<Text>(find.text('hello snippet'));
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('exactly 200 characters are not truncated, 201 are', (
      tester,
    ) async {
      final exact = 'a' * 200;
      final file = File('${tempDir.path}/b.txt')..writeAsStringSync(exact);
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              't',
              type: AttachmentType.text,
              localPath: file.path,
            ),
          ),
        ),
      );
      await pumpUntilFound(tester, find.text(exact));

      final longer = File('${tempDir.path}/c.txt')
        ..writeAsStringSync('b' * 201);
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            key: const ValueKey('long'),
            attachment: _att(
              't2',
              type: AttachmentType.text,
              localPath: longer.path,
            ),
          ),
        ),
      );
      await pumpUntilFound(tester, find.text('${'b' * 200}…'));
    });

    testWidgets('a missing text file degrades to an empty snippet', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              't',
              type: AttachmentType.text,
              localPath: '${tempDir.path}/does_not_exist.txt',
            ),
          ),
        ),
      );
      // Let the failed read settle (condition-driven).
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('an empty text file renders an empty snippet', (tester) async {
      final file = File('${tempDir.path}/e.txt')..writeAsStringSync('');
      await tester.pumpWidget(
        harness(
          AttachmentPreview(
            attachment: _att(
              't',
              type: AttachmentType.text,
              localPath: file.path,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.text(''), findsOneWidget);
    });
  });

  group('AttachmentTile (additional states)', () {
    testWidgets('loading takes precedence over failure for the trailing '
        'widget while the failure text still shows', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentTile(
            attachment: _att('a'),
            isLoading: true,
            failure: const DownloadFailed(),
          ),
        ),
      );
      expect(find.byKey(const Key('attachment_tile_loading')), findsOneWidget);
      expect(find.byKey(const Key('attachment_tile_error_icon')), findsNothing);
      expect(
        find.byKey(const Key('attachment_tile_error_text')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a very long name does not overflow at large text scale', (
      tester,
    ) async {
      setScreenSize(tester, const Size(320, 480));
      await tester.pumpWidget(
        harness(
          AttachmentTile(
            attachment: _att('a', name: 'very_long_file_name_' * 20),
            failure: const UnknownFailure(),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty name renders an empty title', (tester) async {
      await tester.pumpWidget(
        harness(AttachmentTile(attachment: _att('a', name: ''))),
      );
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('failure text uses the theme error colour in light and dark', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          harness(
            AttachmentTile(
              attachment: _att('a'),
              failure: const NetworkUnavailable(),
            ),
            brightness: brightness,
          ),
        );
        final scheme = Theme.of(
          tester.element(find.byKey(const Key('attachment_tile'))),
        ).colorScheme;
        final text = tester.widget<Text>(
          find.byKey(const Key('attachment_tile_error_text')),
        );
        expect(text.style?.color, scheme.error);
        final icon = tester.widget<Icon>(
          find.byKey(const Key('attachment_tile_error_icon')),
        );
        expect(icon.color, scheme.error);
      }
    });

    testWidgets(
      'honours AttachmentLocalizations override for the failure text',
      (tester) async {
        AttachmentLocalizations.messageOverride = (_) => 'translated';
        addTearDown(() => AttachmentLocalizations.messageOverride = null);
        await tester.pumpWidget(
          harness(
            AttachmentTile(attachment: _att('a'), failure: const CacheFailed()),
          ),
        );
        expect(find.text('translated'), findsOneWidget);
      },
    );

    testWidgets('RTL places the thumbnail on the right of the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          AttachmentTile(attachment: _att('a', name: 'doc')),
          textDirection: TextDirection.rtl,
        ),
      );
      expect(
        tester.getCenter(find.byType(AttachmentThumbnail)).dx,
        greaterThan(tester.getCenter(find.text('doc')).dx),
      );
    });

    testWidgets('exposes the title text to semantics and is tappable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        harness(
          AttachmentTile(
            attachment: _att('a', name: 'Quarterly'),
            onTap: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Quarterly'), findsOneWidget);
      final data = tester
          .getSemantics(find.byKey(const Key('attachment_tile')))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, 'Quarterly');
      handle.dispose();
    });

    testWidgets('without onTap tapping is a safe no-op', (tester) async {
      await tester.pumpWidget(harness(AttachmentTile(attachment: _att('a'))));
      await tester.tap(find.byKey(const Key('attachment_tile')));
      expect(tester.takeException(), isNull);
    });
  });

  group('AttachmentErrorView (additional states)', () {
    testWidgets('has no retry button without onRetry', (tester) async {
      await tester.pumpWidget(
        harness(const AttachmentErrorView(failure: CorruptedFile())),
      );
      expect(
        find.byKey(const Key('attachment_error_retry_button')),
        findsNothing,
      );
      expect(
        find.text('This attachment appears to be corrupted.'),
        findsOneWidget,
      );
    });

    testWidgets('retry fires once per tap, including repeated taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        harness(
          AttachmentErrorView(
            failure: const DownloadFailed(),
            onRetry: () => taps++,
          ),
        ),
      );
      final retry = find.byKey(const Key('attachment_error_retry_button'));
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.tap(retry);
      expect(taps, 3);
    });

    testWidgets('every failure shows its own message', (tester) async {
      const failures = <AttachmentFailure>[
        AttachmentNotFound(),
        UnsupportedAttachment(),
        InvalidSource(),
        NetworkUnavailable(),
        ExpiredUrl(),
        Unauthorized(),
        PermissionDenied(),
        InsufficientStorage(),
        RendererFailed(),
        PlaybackFailed(),
        ConversionFailed(),
        RendererDisabledByConfig(),
        ExternalOpenDisabled(),
      ];
      for (final f in failures) {
        await tester.pumpWidget(harness(AttachmentErrorView(failure: f)));
        expect(find.text(f.localizedMessage), findsOneWidget);
      }
    });

    testWidgets('a long override message wraps on a small screen with a '
        'large text scale', (tester) async {
      setScreenSize(tester, const Size(240, 320));
      AttachmentLocalizations.messageOverride = (_) => 'word ' * 6;
      addTearDown(() => AttachmentLocalizations.messageOverride = null);
      await tester.pumpWidget(
        harness(
          AttachmentErrorView(failure: const UnknownFailure(), onRetry: () {}),
          textScale: 1.5,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty message still renders the icon and retry', (
      tester,
    ) async {
      AttachmentLocalizations.messageOverride = (_) => '';
      addTearDown(() => AttachmentLocalizations.messageOverride = null);
      await tester.pumpWidget(
        harness(
          AttachmentErrorView(failure: const UnknownFailure(), onRetry: () {}),
        ),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders in RTL and dark mode', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentErrorView(failure: const ExpiredUrl(), onRetry: () {}),
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('attachment_error_message')), findsOneWidget);
    });
  });

  group('AttachmentList', () {
    testWidgets('shows a tile per attachment and reports the tapped one', (
      tester,
    ) async {
      final items = [_att('1', name: 'One'), _att('2', name: 'Two')];
      Attachment? tapped;
      await tester.pumpWidget(
        harness(
          AttachmentList(
            attachments: items,
            onTapAttachment: (a) => tapped = a,
          ),
        ),
      );
      expect(find.byType(AttachmentTile), findsNWidgets(2));
      await tester.tap(find.text('Two'));
      expect(tapped, items[1]);
      await tester.tap(find.text('One'));
      expect(tapped, items[0]);
    });

    testWidgets('empty list renders nothing and does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const AttachmentList(attachments: [])));
      expect(find.byType(AttachmentTile), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('null onTapAttachment leaves tiles without a tap handler', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(AttachmentList(attachments: [_att('1')])),
      );
      final tile = tester.widget<AttachmentTile>(find.byType(AttachmentTile));
      expect(tile.onTap, isNull);
      await tester.tap(find.byType(AttachmentTile));
      expect(tester.takeException(), isNull);
    });

    testWidgets('is lazy: a 1000 item list builds only visible rows and '
        'scrolls to the end', (tester) async {
      setScreenSize(tester, const Size(400, 600));
      final items = [
        for (var i = 0; i < 1000; i++) _att('$i', name: 'Item $i'),
      ];
      await tester.pumpWidget(harness(AttachmentList(attachments: items)));
      expect(find.byType(AttachmentTile).evaluate().length, lessThan(30));
      await tester.drag(find.byType(ListView), const Offset(0, -500000));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.fling(
        find.byType(ListView),
        const Offset(0, -100000),
        50000,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Item 0'), findsNothing);
    });

    testWidgets('renders in RTL, dark mode and large text', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentList(attachments: [_att('1', name: 'Eins')]),
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
          textScale: 2,
        ),
      );
      expect(find.text('Eins'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('updating the list rebuilds the rows', (tester) async {
      await tester.pumpWidget(
        harness(AttachmentList(attachments: [_att('1', name: 'A')])),
      );
      await tester.pumpWidget(
        harness(
          AttachmentList(
            attachments: [
              _att('1', name: 'A'),
              _att('2', name: 'B'),
            ],
          ),
        ),
      );
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('AttachmentGrid', () {
    testWidgets('lays out thumbnails in the requested column count', (
      tester,
    ) async {
      setScreenSize(tester, const Size(300, 600));
      final items = [for (var i = 0; i < 6; i++) img('$i')];
      await tester.pumpWidget(
        harness(AttachmentGrid(attachments: items, crossAxisCount: 2)),
      );
      final thumbs = find.byType(AttachmentThumbnail);
      expect(thumbs, findsNWidgets(6));
      final firstRowY = tester.getTopLeft(thumbs.at(0)).dy;
      expect(tester.getTopLeft(thumbs.at(1)).dy, firstRowY);
      expect(tester.getTopLeft(thumbs.at(2)).dy, greaterThan(firstRowY));
    });

    testWidgets('shows icons for non-image attachments without throwing', (
      tester,
    ) async {
      setScreenSize(tester, const Size(300, 600));
      final items = [
        _att('p', type: AttachmentType.pdf),
        _att('t', type: AttachmentType.text),
        _att('v', type: AttachmentType.video),
      ];
      await tester.pumpWidget(harness(AttachmentGrid(attachments: items)));
      expect(tester.takeException(), isNull);
      expect(find.byType(Icon), findsNWidgets(3));
      final Icon icon = tester.widget<Icon>(find.byType(Icon).first);
      expect(icon.size, isNotNull);
      expect(icon.size!.isFinite, isTrue);
    });

    testWidgets('default is three columns', (tester) async {
      setScreenSize(tester, const Size(300, 600));
      final items = [for (var i = 0; i < 6; i++) img('$i')];
      await tester.pumpWidget(harness(AttachmentGrid(attachments: items)));
      final thumbs = find.byType(AttachmentThumbnail);
      final y = tester.getTopLeft(thumbs.at(0)).dy;
      expect(tester.getTopLeft(thumbs.at(2)).dy, y);
      expect(tester.getTopLeft(thumbs.at(3)).dy, greaterThan(y));
    });

    testWidgets('tapping a cell reports that attachment', (tester) async {
      final items = [for (var i = 0; i < 4; i++) img('$i')];
      final tapped = <String>[];
      await tester.pumpWidget(
        harness(
          AttachmentGrid(
            attachments: items,
            onTapAttachment: (a) => tapped.add(a.id),
          ),
        ),
      );
      await tester.tap(find.byType(AttachmentThumbnail).at(2));
      await tester.tap(find.byType(AttachmentThumbnail).at(0));
      expect(tapped, ['2', '0']);
    });

    testWidgets('null onTapAttachment is a safe no-op', (tester) async {
      await tester.pumpWidget(harness(AttachmentGrid(attachments: [img('1')])));
      await tester.tap(find.byType(AttachmentThumbnail));
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty grid and single-column grid render', (tester) async {
      await tester.pumpWidget(harness(const AttachmentGrid(attachments: [])));
      expect(find.byType(AttachmentThumbnail), findsNothing);
      await tester.pumpWidget(
        harness(AttachmentGrid(attachments: [img('1')], crossAxisCount: 1)),
      );
      expect(find.byType(AttachmentThumbnail), findsOneWidget);
    });

    testWidgets('a large grid is lazy and scrolls', (tester) async {
      setScreenSize(tester, const Size(300, 400));
      final items = [for (var i = 0; i < 900; i++) img('$i')];
      await tester.pumpWidget(harness(AttachmentGrid(attachments: items)));
      expect(find.byType(AttachmentThumbnail).evaluate().length, lessThan(40));
      await tester.fling(find.byType(GridView), const Offset(0, -2000), 5000);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in RTL on a tiny screen', (tester) async {
      setScreenSize(tester, const Size(120, 200));
      await tester.pumpWidget(
        harness(
          AttachmentGrid(attachments: [img('1'), img('2')], crossAxisCount: 2),
          textDirection: TextDirection.rtl,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byType(AttachmentThumbnail).first).dx,
        greaterThan(tester.getCenter(find.byType(AttachmentThumbnail).last).dx),
      );
    });
  });

  group('AttachmentViewer', () {
    final resolvedAtt = _att(
      'r',
      type: AttachmentType.pdf,
      localPath: '/local/r.pdf',
    );

    RendererRegistry registryOf(List<String> built) =>
        RendererRegistry(renderers: [_FakeRenderer(AttachmentType.pdf, built)]);

    ResolvedAttachment resolvedFor(Attachment a, String path) =>
        ResolvedAttachment(
          attachment: a,
          localPath: path,
          capabilities: AttachmentCapabilities.none,
        );

    testWidgets('an already-resolved attachment is rendered synchronously '
        'without calling resolve', (tester) async {
      var resolveCalls = 0;
      final built = <String>[];
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: resolvedAtt,
            registry: registryOf(built),
            resolve: (a) async {
              resolveCalls++;
              return resolvedFor(a, '/x');
            },
          ),
        ),
      );
      expect(find.text('rendered:/local/r.pdf'), findsOneWidget);
      expect(resolveCalls, 0);
    });

    testWidgets('unresolved: shows the default loader, then the rendered '
        'resolved attachment', (tester) async {
      final completer = Completer<ResolvedAttachment>();
      final unresolved = _att('u', type: AttachmentType.pdf);
      Attachment? seen;
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: unresolved,
            registry: registryOf([]),
            resolve: (a) {
              seen = a;
              return completer.future;
            },
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(seen, unresolved);

      completer.complete(resolvedFor(unresolved, '/cache/u.pdf'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('rendered:/cache/u.pdf'), findsOneWidget);
    });

    testWidgets('uses a custom loadingBuilder', (tester) async {
      final completer = Completer<ResolvedAttachment>();
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att('u'),
            registry: registryOf([]),
            resolve: (_) => completer.future,
            loadingBuilder: (_) => const Text('custom loading'),
          ),
        ),
      );
      expect(find.text('custom loading'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('resolve failure shows the default error text', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att('u'),
            registry: registryOf([]),
            resolve: (_) => Future.error(
              AttachmentResolutionException(const NetworkUnavailable()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Failed to open attachment'), findsOneWidget);
    });

    testWidgets('resolve failure uses a custom errorBuilder with the error', (
      tester,
    ) async {
      Object? received;
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att('u'),
            registry: registryOf([]),
            resolve: (_) => Future.error(StateError('nope')),
            errorBuilder: (context, error) {
              received = error;
              return const Text('custom error');
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('custom error'), findsOneWidget);
      expect(received, isA<StateError>());
    });

    testWidgets('the default resolver surfaces an uninitialized '
        'AttachmentManager as an error rather than crashing', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentViewer(attachment: _att('u'), registry: registryOf([])),
        ),
      );
      await tester.pump();
      expect(find.textContaining('initializeDefault'), findsOneWidget);
    });

    testWidgets('changing to a different unresolved attachment re-resolves', (
      tester,
    ) async {
      final resolved = <String>[];
      Future<ResolvedAttachment> resolve(Attachment a) async {
        resolved.add(a.id);
        return resolvedFor(a, '/cache/${a.id}.pdf');
      }

      Widget build(Attachment a) => harness(
        AttachmentViewer(
          attachment: a,
          registry: registryOf([]),
          resolve: resolve,
        ),
      );
      await tester.pumpWidget(build(_att('one')));
      await tester.pump();
      expect(find.text('rendered:/cache/one.pdf'), findsOneWidget);

      await tester.pumpWidget(build(_att('two')));
      await tester.pump();
      expect(find.text('rendered:/cache/two.pdf'), findsOneWidget);
      expect(resolved, ['one', 'two']);
    });

    testWidgets('rebuilding with an equal attachment does not re-resolve', (
      tester,
    ) async {
      var calls = 0;
      Future<ResolvedAttachment> resolve(Attachment a) async {
        calls++;
        return resolvedFor(a, '/c.pdf');
      }

      Widget build() => harness(
        AttachmentViewer(
          attachment: _att('same'),
          registry: registryOf([]),
          resolve: resolve,
        ),
      );
      await tester.pumpWidget(build());
      await tester.pump();
      await tester.pumpWidget(build());
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('switching from unresolved to resolved renders directly', (
      tester,
    ) async {
      final completer = Completer<ResolvedAttachment>();
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att('a'),
            registry: registryOf([]),
            resolve: (_) => completer.future,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att('a', localPath: '/now/local.pdf'),
            registry: registryOf([]),
            resolve: (_) => completer.future,
          ),
        ),
      );
      expect(find.text('rendered:/now/local.pdf'), findsOneWidget);
    });

    testWidgets('disposing while resolving and completing afterwards is '
        'safe', (tester) async {
      final completer = Completer<ResolvedAttachment>();
      final a = _att('a');
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: a,
            registry: registryOf([]),
            resolve: (_) => completer.future,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      completer.complete(resolvedFor(a, '/late.pdf'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('an attachment of an unregistered type falls back to the '
        'unknown renderer (external-open affordance)', (tester) async {
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att(
              'z',
              type: AttachmentType.unknown,
              localPath: '/z.bin',
            ),
            registry: RendererRegistry(renderers: const []),
          ),
        ),
      );
      expect(find.text('Open externally'), findsOneWidget);
    });

    testWidgets('renders in RTL, dark and small screens while loading', (
      tester,
    ) async {
      setScreenSize(tester, const Size(100, 100));
      final completer = Completer<ResolvedAttachment>();
      await tester.pumpWidget(
        harness(
          AttachmentViewer(
            attachment: _att('a'),
            registry: registryOf([]),
            resolve: (_) => completer.future,
          ),
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _FakeRenderer extends AttachmentRenderer {
  const _FakeRenderer(this.type, this.built);

  @override
  final AttachmentType type;
  final List<String> built;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    built.add(attachment.id);
    return Text('rendered:${attachment.localPath}');
  }
}
