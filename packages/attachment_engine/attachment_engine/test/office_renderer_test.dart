// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Minimal fake [WebViewPlatform] so [WebViewController]/[WebViewWidget]
/// (used by the Office Online fallback) can be constructed in a plain unit
/// test, which has no real platform implementation registered.
class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakeWebViewController(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnWebResourceError(
    void Function(WebResourceError error) onWebResourceError,
  ) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakePlatformInfo extends PlatformInfo {
  const _FakePlatformInfo({required this.isIOS, bool? isAndroid})
    : _isAndroid = isAndroid ?? !isIOS;
  @override
  final bool isIOS;
  final bool _isAndroid;
  @override
  bool get isAndroid => _isAndroid;
}

class _FakeConnectivityChecker implements ConnectivityChecker {
  const _FakeConnectivityChecker(this.online);
  final bool online;
  @override
  Future<bool> hasConnection() async => online;
}

/// Never resolves until [gate] completes — used to hold a fallback chain
/// in flight so the attachment can be swapped before it resumes.
class _DelayedConnectivityChecker implements ConnectivityChecker {
  _DelayedConnectivityChecker(this.gate);
  final Completer<void> gate;
  @override
  Future<bool> hasConnection() async {
    await gate.future;
    return false;
  }
}

class _FakeConversionStrategy implements OfficeConversionStrategy {
  const _FakeConversionStrategy(this.result);
  final String? result;
  @override
  Future<String?> convert(Attachment attachment) async => result;
}

/// Records which [AttachmentEnginePlatform] methods the renderer invokes,
/// standing in for the real iOS/Android platform packages (which this
/// package cannot depend on without a cycle).
class _RecordingPlatform extends AttachmentEnginePlatform {
  final List<String> calls = [];

  @override
  Future<void> openOfficePreview(String path) async {
    calls.add('openOfficePreview:$path');
  }

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    calls.add('openExternally:$path');
    return const NativeOpenResult(success: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Attachment officeAttachment(String localPath, {String? remoteUrl}) =>
      Attachment(
        id: 'a1',
        name: 'file.docx',
        source: const AttachmentSource.url('https://example.com/f.docx'),
        remoteUrl: remoteUrl,
        attachmentType: AttachmentType.office,
        status: AttachmentStatus.ready,
        localPath: localPath,
      );

  late _RecordingPlatform platform;

  setUp(() {
    platform = _RecordingPlatform();
    AttachmentEnginePlatform.instance = platform;
    WebViewPlatform.instance = _FakeWebViewPlatform();
  });

  group('OfficeAttachmentRenderer platform strategy', () {
    testWidgets('iOS uses the in-app QuickLook preview channel', (
      tester,
    ) async {
      final renderer = OfficeAttachmentRenderer(
        platformInfo: const _FakePlatformInfo(isIOS: true),
        connectivityChecker: const _FakeConnectivityChecker(false),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) =>
                renderer.build(context, officeAttachment('/tmp/f.docx')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(platform.calls, ['openOfficePreview:/tmp/f.docx']);
      expect(
        tester.widget<Text>(find.byType(Text)).data,
        'Opened in the in-app document viewer.',
      );
    });

    testWidgets(
      'iOS calls onDismissed once the QuickLook preview future resolves '
      '(i.e. once the user has dismissed it)',
      (tester) async {
        var dismissed = 0;
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: true),
          onDismissed: () => dismissed++,
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, officeAttachment('/tmp/f.docx')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(dismissed, 1);
      },
    );

    testWidgets('Android with no connection and no public URL falls back to '
        'external-open', (tester) async {
      final renderer = OfficeAttachmentRenderer(
        platformInfo: const _FakePlatformInfo(isIOS: false),
        connectivityChecker: const _FakeConnectivityChecker(false),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) =>
                renderer.build(context, officeAttachment('/tmp/f.docx')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(platform.calls, ['openExternally:/tmp/f.docx']);
      expect(
        tester.widget<Text>(find.byType(Text)).data,
        'Opened in an external viewer.',
      );
    });

    testWidgets(
      'Android online with a public URL prefers the in-app Office Online '
      'viewer over external-open',
      (tester) async {
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: false),
          connectivityChecker: const _FakeConnectivityChecker(true),
          isUrlSafeForOfficeOnline: (_) => true,
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                officeAttachment(
                  '/tmp/f.docx',
                  remoteUrl: 'https://cdn.example.com/f.docx',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No external-open or QuickLook call — it stayed in-app via
        // Office Online instead.
        expect(platform.calls, isEmpty);
        expect(find.byType(WebViewWidget), findsOneWidget);
      },
    );

    testWidgets(
      'Office Online is skipped by default (no isUrlSafeForOfficeOnline '
      'supplied), even with a public URL and a connection, to avoid '
      "leaking a possibly-private/signed URL to Microsoft's servers",
      (tester) async {
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: false),
          connectivityChecker: const _FakeConnectivityChecker(true),
          // isUrlSafeForOfficeOnline intentionally omitted.
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                officeAttachment(
                  '/tmp/f.docx',
                  remoteUrl: 'https://cdn.example.com/f.docx?sig=secret',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WebViewWidget), findsNothing);
        // No Office Online usable and no conversionStrategy supplied — it
        // falls all the way through to external-open.
        expect(platform.calls, ['openExternally:/tmp/f.docx']);
      },
    );

    testWidgets(
      'a successful conversion renders in-app as a PDF when Office Online '
      "isn't usable (Android, offline/no public URL)",
      (tester) async {
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: false),
          connectivityChecker: const _FakeConnectivityChecker(false),
          conversionStrategy: const _FakeConversionStrategy(
            '/tmp/converted.pdf',
          ),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, officeAttachment('/tmp/f.docx')),
            ),
          ),
        );
        await tester.pump();

        // No external-open, no QuickLook, no Office Online WebView — the
        // conversion path only kicks in once nothing better is available.
        expect(platform.calls, isEmpty);
        expect(find.byType(WebViewWidget), findsNothing);
      },
    );

    testWidgets(
      'Office Online is preferred over a supplied conversionStrategy when '
      'both are usable',
      (tester) async {
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: false),
          connectivityChecker: const _FakeConnectivityChecker(true),
          conversionStrategy: const _FakeConversionStrategy(
            '/tmp/converted.pdf',
          ),
          isUrlSafeForOfficeOnline: (_) => true,
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                officeAttachment(
                  '/tmp/f.docx',
                  remoteUrl: 'https://cdn.example.com/f.docx',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(platform.calls, isEmpty);
        expect(find.byType(WebViewWidget), findsOneWidget);
      },
    );

    testWidgets(
      'a platform that is neither iOS nor Android reports "not supported" '
      'instead of attempting Android-only behavior',
      (tester) async {
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: false, isAndroid: false),
          connectivityChecker: const _FakeConnectivityChecker(true),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                officeAttachment(
                  '/tmp/f.docx',
                  remoteUrl: 'https://cdn.example.com/f.docx',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(platform.calls, isEmpty);
        expect(find.byType(WebViewWidget), findsNothing);
        expect(
          find.text("Office documents aren't supported on this platform."),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reusing the same renderer/widget for a different attachment reopens '
      'instead of keeping the previous document',
      (tester) async {
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: true),
        );

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, officeAttachment('/tmp/a.docx')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(platform.calls, ['openOfficePreview:/tmp/a.docx']);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, officeAttachment('/tmp/b.docx')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(platform.calls, [
          'openOfficePreview:/tmp/a.docx',
          'openOfficePreview:/tmp/b.docx',
        ]);
      },
    );

    testWidgets(
      'a stale fallback chain (attachment swapped while its connectivity '
      'check was still in flight) does not open the previous attachment '
      'externally once it resumes',
      (tester) async {
        final gate = Completer<void>();
        final renderer = OfficeAttachmentRenderer(
          platformInfo: const _FakePlatformInfo(isIOS: false),
          connectivityChecker: _DelayedConnectivityChecker(gate),
          isUrlSafeForOfficeOnline: (_) => true,
        );

        // Start opening attachment A — its connectivityChecker.hasConnection()
        // call hangs on `gate` and never resolves during this pump.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                officeAttachment(
                  '/tmp/a.docx',
                  remoteUrl: 'https://cdn.example.com/a.docx',
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Swap to attachment B before A's fallback chain has resumed.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                officeAttachment(
                  '/tmp/b.docx',
                  remoteUrl: 'https://cdn.example.com/b.docx',
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Now let A's stale chain resume: hasConnection() resolves false,
        // no conversionStrategy is supplied, so it falls through to
        // external-open — for the WRONG (no-longer-current) attachment.
        gate.complete();
        await tester.pumpAndSettle();

        expect(platform.calls, isNot(contains('openExternally:/tmp/a.docx')));
      },
    );
  });
}
