// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'helpers/fake_webview.dart';
import 'helpers/widget_harness.dart';

typedef _ViewerBuilder = Widget Function(String path, VoidCallback? onFailed);

class _Variant {
  const _Variant(this.name, this.asset, this.renderFn, this.build);
  final String name;
  final String asset;
  final String renderFn;
  final _ViewerBuilder build;
}

final _variants = <_Variant>[
  _Variant(
    'OfflineDocxViewer',
    'packages/attachment_engine/assets/office_offline/docx_viewer.html',
    'renderDocx',
    (path, onFailed) => OfflineDocxViewer(localPath: path, onFailed: onFailed),
  ),
  _Variant(
    'OfflinePptxViewer',
    'packages/attachment_engine/assets/office_offline/pptx_viewer.html',
    'renderPptx',
    (path, onFailed) => OfflinePptxViewer(localPath: path, onFailed: onFailed),
  ),
  _Variant(
    'OfflineSpreadsheetViewer',
    'packages/attachment_engine/assets/office_offline/xlsx_viewer.html',
    'renderSpreadsheet',
    (path, onFailed) =>
        OfflineSpreadsheetViewer(localPath: path, onFailed: onFailed),
  ),
];

void main() {
  late Directory tempDir;
  late FakeWebViewPlatform webview;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('offline_viewers_test');
    webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File doc(String name, List<int> bytes) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(bytes);

  for (final v in _variants) {
    group(v.name, () {
      testWidgets('loads its bundled shell, enables JS and registers the '
          'error channel', (tester) async {
        final file = doc('a.bin', [1, 2, 3]);
        await tester.pumpWidget(harness(v.build(file.path, null)));
        final c = webview.controllers.single;
        expect(c.loadedAssets, [v.asset]);
        expect(c.javaScriptMode, JavaScriptMode.unrestricted);
        expect(c.channels.keys, ['OfflineDocViewer']);
        expect(find.byType(WebViewWidget), findsOneWidget);
        expect(c.scripts, isEmpty);
      });

      testWidgets('once the shell finishes loading it sends the document as '
          'base64 exactly once', (tester) async {
        final bytes = List<int>.generate(200000, (i) => i % 251);
        final file = doc('big.bin', bytes);
        await tester.pumpWidget(harness(v.build(file.path, () {})));
        final c = webview.controllers.single;
        c.navigationDelegate!.onPageFinished!('about:blank');
        // A second page-finished (in-page navigation) must not re-render.
        c.navigationDelegate!.onPageFinished!('about:blank');
        await pumpUntil(
          tester,
          () => c.scripts.isNotEmpty,
          reason: 'render script',
        );
        await tester.pump();
        expect(c.scripts, hasLength(1));
        expect(c.scripts.single, '${v.renderFn}("${base64Encode(bytes)}")');
      });

      testWidgets('an empty document is still sent (empty base64)', (
        tester,
      ) async {
        final file = doc('empty.bin', []);
        await tester.pumpWidget(harness(v.build(file.path, () {})));
        final c = webview.controllers.single;
        c.navigationDelegate!.onPageFinished!('x');
        await pumpUntil(tester, () => c.scripts.isNotEmpty, reason: 'script');
        expect(c.scripts.single, '${v.renderFn}("")');
      });

      testWidgets('a missing file reports failure once', (tester) async {
        var failed = 0;
        await tester.pumpWidget(
          harness(v.build('${tempDir.path}/missing.bin', () => failed++)),
        );
        final c = webview.controllers.single;
        c.navigationDelegate!.onPageFinished!('x');
        await pumpUntil(tester, () => failed > 0, reason: 'onFailed');
        await tester.pump();
        expect(failed, 1);
        expect(c.scripts, isEmpty);
      });

      testWidgets('a JavaScript evaluation error reports failure', (
        tester,
      ) async {
        var failed = 0;
        final file = doc('a.bin', [1]);
        await tester.pumpWidget(harness(v.build(file.path, () => failed++)));
        webview.scriptError = StateError('js boom');
        webview.controllers.single.navigationDelegate!.onPageFinished!('x');
        await pumpUntil(tester, () => failed > 0, reason: 'onFailed');
        expect(failed, 1);
      });

      testWidgets('an "error:" message from the page reports failure; other '
          'messages are ignored', (tester) async {
        var failed = 0;
        await tester.pumpWidget(
          harness(v.build(doc('a.bin', [1]).path, () => failed++)),
        );
        final channel =
            webview.controllers.single.channels['OfflineDocViewer']!;
        channel(const JavaScriptMessage(message: 'ready'));
        channel(const JavaScriptMessage(message: ''));
        channel(const JavaScriptMessage(message: 'Error: capitalised'));
        expect(failed, 0);
        channel(const JavaScriptMessage(message: 'error: bad zip'));
        expect(failed, 1);
      });

      testWidgets('repeated resource errors only report failure once', (
        tester,
      ) async {
        var failed = 0;
        await tester.pumpWidget(
          harness(v.build(doc('a.bin', [1]).path, () => failed++)),
        );
        final d = webview.controllers.single.navigationDelegate!;
        d.onWebResourceError!(fakeWebResourceError());
        d.onWebResourceError!(fakeWebResourceError());
        webview.controllers.single.channels['OfflineDocViewer']!(
          const JavaScriptMessage(message: 'error:again'),
        );
        expect(failed, 1);
      });

      testWidgets('failures with no onFailed callback are safe', (
        tester,
      ) async {
        await tester.pumpWidget(harness(v.build(doc('a.bin', [1]).path, null)));
        webview.controllers.single.navigationDelegate!.onWebResourceError!(
          fakeWebResourceError(),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('errors arriving after disposal are ignored', (tester) async {
        var failed = 0;
        await tester.pumpWidget(
          harness(v.build(doc('a.bin', [1]).path, () => failed++)),
        );
        final c = webview.controllers.single;
        await tester.pumpWidget(const SizedBox());
        c.navigationDelegate!.onWebResourceError!(fakeWebResourceError());
        c.channels['OfflineDocViewer']!(
          const JavaScriptMessage(message: 'error:late'),
        );
        expect(failed, 0);
      });

      testWidgets('disposing while the file is being read does not crash', (
        tester,
      ) async {
        final file = doc('a.bin', List<int>.filled(300000, 7));
        await tester.pumpWidget(harness(v.build(file.path, () {})));
        webview.controllers.single.navigationDelegate!.onPageFinished!('x');
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('rebuilding with the same path keeps the controller', (
        tester,
      ) async {
        final file = doc('a.bin', [1]);
        await tester.pumpWidget(harness(v.build(file.path, null)));
        await tester.pumpWidget(harness(v.build(file.path, null)));
        expect(webview.controllers, hasLength(1));
      });

      testWidgets('switching to a different document rebuilds the controller, '
          're-arms rendering and resets the failed flag', (tester) async {
        var failed = 0;
        final first = doc('one.bin', [1, 1]);
        final second = doc('two.bin', [2, 2, 2]);
        await tester.pumpWidget(harness(v.build(first.path, () => failed++)));
        final c1 = webview.controllers.single;
        c1.navigationDelegate!.onPageFinished!('x');
        await pumpUntil(tester, () => c1.scripts.isNotEmpty, reason: 'first');
        c1.navigationDelegate!.onWebResourceError!(fakeWebResourceError());
        expect(failed, 1);

        await tester.pumpWidget(harness(v.build(second.path, () => failed++)));
        expect(webview.controllers, hasLength(2));
        final c2 = webview.controllers.last;
        expect(c2.loadedAssets, [v.asset]);
        c2.navigationDelegate!.onPageFinished!('x');
        await pumpUntil(tester, () => c2.scripts.isNotEmpty, reason: 'second');
        expect(
          c2.scripts.single,
          '${v.renderFn}("${base64Encode([2, 2, 2])}")',
        );

        c2.navigationDelegate!.onWebResourceError!(fakeWebResourceError());
        expect(failed, 2);
      });
    });
  }
}
