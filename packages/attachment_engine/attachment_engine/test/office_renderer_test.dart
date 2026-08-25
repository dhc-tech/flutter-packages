// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatformInfo extends PlatformInfo {
  const _FakePlatformInfo({required this.isIOS});
  @override
  final bool isIOS;
  @override
  bool get isAndroid => !isIOS;
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

  Attachment officeAttachment(String localPath) => Attachment(
    id: 'a1',
    name: 'file.docx',
    source: const AttachmentSource.url('https://example.com/f.docx'),
    remoteUrl: 'https://example.com/f.docx',
    attachmentType: AttachmentType.office,
    status: AttachmentStatus.ready,
    localPath: localPath,
  );

  late _RecordingPlatform platform;

  setUp(() {
    platform = _RecordingPlatform();
    AttachmentEnginePlatform.instance = platform;
  });

  group('OfficeAttachmentRenderer platform strategy', () {
    testWidgets('iOS uses the in-app QuickLook preview channel', (
      tester,
    ) async {
      const renderer = OfficeAttachmentRenderer(
        platformInfo: _FakePlatformInfo(isIOS: true),
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

    testWidgets('Android falls back to external-open', (tester) async {
      const renderer = OfficeAttachmentRenderer(
        platformInfo: _FakePlatformInfo(isIOS: false),
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
  });
}
