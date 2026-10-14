// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'helpers/fake_webview.dart';
import 'helpers/widget_harness.dart';

class _Info extends PlatformInfo {
  const _Info({this.ios = false, this.android = false});
  final bool ios;
  final bool android;
  @override
  bool get isIOS => ios;
  @override
  bool get isAndroid => android;
}

class _Conn implements ConnectivityChecker {
  _Conn(this.result, {this.error});
  final bool result;
  final Object? error;
  @override
  Future<bool> hasConnection() async {
    if (error != null) throw error!;
    return result;
  }
}

class _GatedConn implements ConnectivityChecker {
  final gate = Completer<bool>();
  @override
  Future<bool> hasConnection() => gate.future;
}

class _Convert implements OfficeConversionStrategy {
  _Convert(this.result, {this.error});
  final String? result;
  final Object? error;
  int calls = 0;
  @override
  Future<String?> convert(Attachment attachment) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

class _Platform extends AttachmentEnginePlatform {
  final List<String> opened = [];
  final List<String> previewed = [];
  final List<String> pdfOpened = [];
  NativeOpenResult openResult = const NativeOpenResult(success: true);
  Object? previewError;

  @override
  Future<void> openOfficePreview(String path) async {
    if (previewError != null) throw previewError!;
    previewed.add(path);
  }

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    opened.add(path);
    return openResult;
  }

  @override
  Future<PdfOpenResult> pdfOpen(String path) async {
    pdfOpened.add(path);
    return PdfOpenResult(handle: path, pageCount: 1);
  }

  @override
  Future<List<int>> pdfRenderPage(
    String handle,
    int index, {
    required int width,
    required int height,
  }) async => kTinyPng;

  @override
  Future<void> pdfClose(String handle) async {}
}

Attachment _doc({
  String id = 'o1',
  String? ext = 'doc',
  String? localPath = '/tmp/f.doc',
  String? remoteUrl,
  AttachmentSource source = const AttachmentSource.url('https://e.com/f.doc'),
}) => Attachment(
  id: id,
  name: 'f.$ext',
  source: source,
  remoteUrl: remoteUrl,
  extension: ext,
  attachmentType: AttachmentType.office,
  localPath: localPath,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Platform platform;
  late FakeWebViewPlatform webview;

  setUp(() {
    platform = _Platform();
    AttachmentEnginePlatform.instance = platform;
    webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
  });

  Widget host(OfficeAttachmentRenderer r, Attachment a) =>
      harness(Builder(builder: (c) => r.build(c, a)));

  OfficeAttachmentRenderer renderer({
    PlatformInfo info = const _Info(android: true),
    OfficeConversionStrategy? convert,
    ExternalOpenConfig external = const ExternalOpenConfig(),
    ConnectivityChecker? conn,
    bool Function(Attachment)? safe,
    VoidCallback? onDismissed,
  }) => OfficeAttachmentRenderer(
    platformInfo: info,
    conversionStrategy: convert,
    externalOpenConfig: external,
    connectivityChecker: conn ?? _Conn(true),
    isUrlSafeForOfficeOnline: safe,
    onDismissed: onDismissed,
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  test('type is office', () => expect(renderer().type, AttachmentType.office));

  group('iOS', () {
    testWidgets('opens the QuickLook preview and reports dismissal', (
      tester,
    ) async {
      var dismissed = 0;
      await tester.pumpWidget(
        host(
          renderer(
            info: const _Info(ios: true),
            onDismissed: () => dismissed++,
          ),
          _doc(),
        ),
      );
      await settle(tester);
      expect(platform.previewed, ['/tmp/f.doc']);
      expect(
        find.text('Opened in the in-app document viewer.'),
        findsOneWidget,
      );
      expect(dismissed, 1);
    });

    testWidgets('no local file is an error and never calls the platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(renderer(info: const _Info(ios: true)), _doc(localPath: null)),
      );
      await settle(tester);
      expect(find.text('No local file to open.'), findsOneWidget);
      expect(platform.previewed, isEmpty);
    });

    testWidgets(
      'a platform failure shows a generic error and does not dismiss',
      (tester) async {
        platform.previewError = StateError('quicklook failed');
        var dismissed = 0;
        await tester.pumpWidget(
          host(
            renderer(
              info: const _Info(ios: true),
              onDismissed: () => dismissed++,
            ),
            _doc(),
          ),
        );
        await settle(tester);
        expect(find.text('Unable to open this document.'), findsOneWidget);
        expect(dismissed, 0);
      },
    );
  });

  testWidgets('an unsupported platform reports it', (tester) async {
    await tester.pumpWidget(host(renderer(info: const _Info()), _doc()));
    await settle(tester);
    expect(
      find.textContaining("aren't supported on this platform"),
      findsOneWidget,
    );
    expect(platform.opened, isEmpty);
  });

  group('Android offline viewers', () {
    final cases = <String, Type>{
      'docx': OfflineDocxViewer,
      'DOCX': OfflineDocxViewer,
      'xlsx': OfflineSpreadsheetViewer,
      'xls': OfflineSpreadsheetViewer,
      'xlsm': OfflineSpreadsheetViewer,
      'pptx': OfflinePptxViewer,
    };
    for (final e in cases.entries) {
      testWidgets('.${e.key} uses ${e.value}', (tester) async {
        await tester.pumpWidget(
          host(renderer(), _doc(ext: e.key, localPath: '/tmp/f.${e.key}')),
        );
        await settle(tester);
        expect(find.byType(e.value), findsOneWidget);
        expect(platform.opened, isEmpty);
      });
    }

    testWidgets(
      'an extension-less or unsupported format skips the offline viewers',
      (tester) async {
        await tester.pumpWidget(host(renderer(), _doc(ext: null)));
        await settle(tester);
        expect(find.byType(OfflineDocxViewer), findsNothing);
        expect(platform.opened, ['/tmp/f.doc']);
      },
    );

    testWidgets('an offline-capable format with no local file does not use '
        'the viewers', (tester) async {
      await tester.pumpWidget(
        host(renderer(), _doc(ext: 'docx', localPath: null)),
      );
      await settle(tester);
      expect(find.byType(OfflineDocxViewer), findsNothing);
      expect(find.text('No local file to open.'), findsOneWidget);
    });

    testWidgets(
      'when the offline viewer fails it falls through to external open',
      (tester) async {
        await tester.pumpWidget(
          host(renderer(), _doc(ext: 'docx', localPath: '/tmp/f.docx')),
        );
        await settle(tester);
        webview.controllers.single.navigationDelegate!.onWebResourceError!(
          fakeWebResourceError(),
        );
        await settle(tester);
        expect(find.byType(OfflineDocxViewer), findsNothing);
        expect(platform.opened, ['/tmp/f.docx']);
        expect(find.text('Opened in an external viewer.'), findsOneWidget);
      },
    );

    testWidgets('an offline failure can fall through to a conversion', (
      tester,
    ) async {
      final convert = _Convert('/tmp/converted.pdf');
      await tester.pumpWidget(
        host(
          renderer(convert: convert),
          _doc(ext: 'xlsx', localPath: '/tmp/f.xlsx'),
        ),
      );
      await settle(tester);
      webview.controllers.single.navigationDelegate!.onWebResourceError!(
        fakeWebResourceError(),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 10));
      expect(convert.calls, 1);
      expect(platform.pdfOpened, ['/tmp/converted.pdf']);
    });
  });

  group('Android Office Online', () {
    final remote = _doc(remoteUrl: 'https://e.com/a b.doc');

    testWidgets('is shown for a safe public url with a connection', (
      tester,
    ) async {
      await tester.pumpWidget(host(renderer(safe: (_) => true), remote));
      await settle(tester);
      expect(find.byType(WebViewWidget), findsOneWidget);
      expect(
        webview.controllers.single.loadedRequests.single.toString(),
        'https://view.officeapps.live.com/op/view.aspx?src=${Uri.encodeComponent('https://e.com/a b.doc')}',
      );
      expect(platform.opened, isEmpty);
    });

    testWidgets('falls back to the url source when remoteUrl is unset', (
      tester,
    ) async {
      await tester.pumpWidget(host(renderer(safe: (_) => true), _doc()));
      await settle(tester);
      expect(
        webview.controllers.single.loadedRequests.single.queryParameters['src'],
        'https://e.com/f.doc',
      );
    });

    testWidgets('is skipped when no safety predicate is given', (tester) async {
      await tester.pumpWidget(host(renderer(), remote));
      await settle(tester);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(platform.opened, ['/tmp/f.doc']);
    });

    testWidgets('is skipped when the predicate says the url is unsafe', (
      tester,
    ) async {
      await tester.pumpWidget(host(renderer(safe: (_) => false), remote));
      await settle(tester);
      expect(webview.controllers, isEmpty);
      expect(platform.opened, hasLength(1));
    });

    testWidgets('is skipped without a public url', (tester) async {
      await tester.pumpWidget(
        host(
          renderer(safe: (_) => true),
          _doc(source: const AttachmentSource.file('/tmp/f.doc')),
        ),
      );
      await settle(tester);
      expect(webview.controllers, isEmpty);
    });

    testWidgets(
      'is skipped when offline or when the connectivity check throws',
      (tester) async {
        await tester.pumpWidget(
          host(renderer(safe: (_) => true, conn: _Conn(false)), remote),
        );
        await settle(tester);
        expect(webview.controllers, isEmpty);
        expect(platform.opened, hasLength(1));

        platform.opened.clear();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          host(
            renderer(
              safe: (_) => true,
              conn: _Conn(true, error: StateError('dns')),
            ),
            _doc(id: 'o2'),
          ),
        );
        await settle(tester);
        expect(webview.controllers, isEmpty);
        expect(platform.opened, hasLength(1));
      },
    );

    testWidgets(
      'a load error falls through to conversion, then to external open',
      (tester) async {
        final convert = _Convert(null);
        await tester.pumpWidget(
          host(renderer(safe: (_) => true, convert: convert), remote),
        );
        await settle(tester);
        webview.controllers.single.navigationDelegate!.onWebResourceError!(
          fakeWebResourceError(),
        );
        webview.controllers.single.navigationDelegate!.onWebResourceError!(
          fakeWebResourceError(),
        );
        await settle(tester);
        expect(find.byType(WebViewWidget), findsNothing);
        expect(convert.calls, 1);
        expect(platform.opened, ['/tmp/f.doc']);
      },
    );

    testWidgets(
      'a load error with a converting strategy shows the converted pdf',
      (tester) async {
        final convert = _Convert('/tmp/c.pdf');
        await tester.pumpWidget(
          host(renderer(safe: (_) => true, convert: convert), remote),
        );
        await settle(tester);
        webview.controllers.single.navigationDelegate!.onWebResourceError!(
          fakeWebResourceError(),
        );
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 10));
        expect(platform.pdfOpened, ['/tmp/c.pdf']);
        expect(platform.opened, isEmpty);
      },
    );

    testWidgets(
      'a throwing conversion after an Office Online failure falls to external open',
      (tester) async {
        await tester.pumpWidget(
          host(
            renderer(
              safe: (_) => true,
              convert: _Convert(null, error: StateError('x')),
            ),
            remote,
          ),
        );
        await settle(tester);
        webview.controllers.single.navigationDelegate!.onWebResourceError!(
          fakeWebResourceError(),
        );
        await settle(tester);
        expect(platform.opened, ['/tmp/f.doc']);
      },
    );
  });

  group('Android conversion and external fallbacks', () {
    testWidgets('a conversion result is rendered as a pdf', (tester) async {
      final convert = _Convert('/tmp/conv.pdf');
      await tester.pumpWidget(host(renderer(convert: convert), _doc()));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 10));
      expect(platform.pdfOpened, ['/tmp/conv.pdf']);
      expect(platform.opened, isEmpty);
    });

    testWidgets('a null or throwing conversion falls to external open', (
      tester,
    ) async {
      await tester.pumpWidget(host(renderer(convert: _Convert(null)), _doc()));
      await settle(tester);
      expect(platform.opened, ['/tmp/f.doc']);

      platform.opened.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(
          renderer(convert: _Convert(null, error: StateError('x'))),
          _doc(id: 'o2'),
        ),
      );
      await settle(tester);
      expect(platform.opened, ['/tmp/f.doc']);
    });

    testWidgets('external open disabled shows the disabled message', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          renderer(
            external: const ExternalOpenConfig(allowExternalFallback: false),
          ),
          _doc(),
        ),
      );
      await settle(tester);
      expect(
        find.text('Opening this attachment externally is disabled.'),
        findsOneWidget,
      );
      expect(platform.opened, isEmpty);
    });

    testWidgets('a failed external open surfaces the platform message', (
      tester,
    ) async {
      platform.openResult = const NativeOpenResult(
        success: false,
        message: 'No app can open this',
      );
      await tester.pumpWidget(host(renderer(), _doc()));
      await settle(tester);
      expect(find.text('No app can open this'), findsOneWidget);
    });

    testWidgets(
      'a failed external open with no message renders without error',
      (tester) async {
        platform.openResult = const NativeOpenResult(success: false);
        await tester.pumpWidget(host(renderer(), _doc()));
        await settle(tester);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no local file reports it', (tester) async {
      await tester.pumpWidget(host(renderer(), _doc(localPath: null)));
      await settle(tester);
      expect(find.text('No local file to open.'), findsOneWidget);
    });

    testWidgets('shows a progress placeholder while still opening', (
      tester,
    ) async {
      final conn = _GatedConn();
      await tester.pumpWidget(
        host(
          renderer(conn: conn, safe: (_) => true),
          _doc(remoteUrl: 'https://e.com/x'),
        ),
      );
      await tester.pump();
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('Opened'), findsNothing);
      conn.gate.complete(false);
      await settle(tester);
      expect(platform.opened, hasLength(1));
    });
  });

  group('attachment changes', () {
    testWidgets('switching attachments resets state and reopens', (
      tester,
    ) async {
      final r = renderer();
      await tester.pumpWidget(host(r, _doc(id: 'a', localPath: '/tmp/a.doc')));
      await settle(tester);
      await tester.pumpWidget(host(r, _doc(id: 'b', localPath: '/tmp/b.doc')));
      await settle(tester);
      expect(platform.opened, ['/tmp/a.doc', '/tmp/b.doc']);
    });

    testWidgets(
      'a stale chain from the previous attachment never opens an app',
      (tester) async {
        final slow = _GatedConn();
        final slowRenderer = OfficeAttachmentRenderer(
          platformInfo: const _Info(android: true),
          connectivityChecker: slow,
          isUrlSafeForOfficeOnline: (_) => true,
        );
        await tester.pumpWidget(
          host(
            slowRenderer,
            _doc(
              id: 'old',
              localPath: '/tmp/old.doc',
              remoteUrl: 'https://e.com/o',
            ),
          ),
        );
        await tester.pump();
        final fastRenderer = OfficeAttachmentRenderer(
          platformInfo: const _Info(android: true),
          connectivityChecker: _Conn(false),
        );
        await tester.pumpWidget(
          host(fastRenderer, _doc(id: 'new', localPath: '/tmp/new.doc')),
        );
        await settle(tester);
        slow.gate.complete(false);
        await settle(tester);
        expect(platform.opened, ['/tmp/new.doc']);
      },
    );

    testWidgets('disposing mid-open is safe', (tester) async {
      final slow = _GatedConn();
      await tester.pumpWidget(
        host(
          renderer(conn: slow, safe: (_) => true),
          _doc(remoteUrl: 'https://e.com/o'),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      slow.gate.complete(false);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(platform.opened, isEmpty);
    });
  });
}
