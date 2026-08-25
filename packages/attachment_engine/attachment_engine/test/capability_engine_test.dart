import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatformInfo extends PlatformInfo {
  const _FakePlatformInfo({required this.isIOS});
  @override
  final bool isIOS;
  @override
  bool get isAndroid => !isIOS;
}

void main() {
  const engine = CapabilityEngine();

  Attachment build({
    AttachmentType type = AttachmentType.pdf,
    AttachmentStatus status = AttachmentStatus.ready,
    AttachmentSource source = const AttachmentSource.url(
      'https://example.com/f.pdf',
    ),
    String? remoteUrl = 'https://example.com/f.pdf',
  }) {
    return Attachment(
      id: 'a1',
      name: 'file',
      source: source,
      remoteUrl: remoteUrl,
      attachmentType: type,
      status: status,
    );
  }

  group('CapabilityEngine per status', () {
    test(
      'ready attachment can preview/open/share/cache/openExternally/deleteCache',
      () {
        final caps = engine.derive(build(status: AttachmentStatus.ready));
        expect(caps.canPreview, isTrue);
        expect(caps.canOpen, isTrue);
        expect(caps.canShare, isTrue);
        expect(caps.canCache, isTrue);
        expect(caps.canOpenExternally, isTrue);
        expect(caps.canDeleteCache, isTrue);
      },
    );

    test('failed attachment has no preview/open/share/cache capability', () {
      final caps = engine.derive(build(status: AttachmentStatus.failed));
      expect(caps.canPreview, isFalse);
      expect(caps.canOpen, isFalse);
      expect(caps.canShare, isFalse);
      expect(caps.canCache, isFalse);
    });

    test('cleaned attachment can only be re-downloaded', () {
      final caps = engine.derive(build(status: AttachmentStatus.cleaned));
      expect(caps.canDownload, isTrue);
      expect(caps.canOpen, isFalse);
      expect(caps.canPreview, isFalse);
      expect(caps.canDeleteCache, isFalse);
    });

    test(
      'discovered attachment (not yet fetched) can preview but not open/play',
      () {
        final caps = engine.derive(build(status: AttachmentStatus.discovered));
        expect(caps.canPreview, isTrue);
        expect(caps.canOpen, isFalse);
        expect(caps.canPlay, isFalse);
      },
    );
  });

  group('CapabilityEngine per type', () {
    test('video attachment that is ready can play', () {
      final caps = engine.derive(
        build(type: AttachmentType.video, status: AttachmentStatus.ready),
      );
      expect(caps.canPlay, isTrue);
    });

    test('audio attachment that is ready can play', () {
      final caps = engine.derive(
        build(type: AttachmentType.audio, status: AttachmentStatus.ready),
      );
      expect(caps.canPlay, isTrue);
    });

    test('pdf attachment that is ready cannot play (not audio/video)', () {
      final caps = engine.derive(
        build(type: AttachmentType.pdf, status: AttachmentStatus.ready),
      );
      expect(caps.canPlay, isFalse);
    });

    test('unknown type cannot be previewed even when ready', () {
      final caps = engine.derive(
        build(type: AttachmentType.unknown, status: AttachmentStatus.ready),
      );
      expect(caps.canPreview, isFalse);
    });

    test('bytes source cannot be downloaded (nothing remote to fetch)', () {
      final caps = engine.derive(
        build(
          source: AttachmentSource.bytes(Uint8List(0)),
          remoteUrl: null,
          status: AttachmentStatus.ready,
        ),
      );
      expect(caps.canDownload, isFalse);
    });

    test('cache source cannot be re-cached', () {
      final caps = engine.derive(
        build(
          source: const AttachmentSource.cache('key'),
          remoteUrl: null,
          status: AttachmentStatus.ready,
        ),
      );
      expect(caps.canCache, isFalse);
    });
  });

  group('CapabilityEngine office platform asymmetry', () {
    test('office attachment on iOS can preview in-app (QuickLook)', () {
      const iosEngine = CapabilityEngine(
        platformInfo: _FakePlatformInfo(isIOS: true),
      );
      final caps = iosEngine.derive(
        build(type: AttachmentType.office, status: AttachmentStatus.ready),
      );
      expect(caps.canPreview, isTrue);
      expect(caps.canOpenExternally, isTrue);
    });

    test(
      'office attachment on Android cannot preview in-app, only externally',
      () {
        const androidEngine = CapabilityEngine(
          platformInfo: _FakePlatformInfo(isIOS: false),
        );
        final caps = androidEngine.derive(
          build(type: AttachmentType.office, status: AttachmentStatus.ready),
        );
        expect(caps.canPreview, isFalse);
        expect(caps.canOpenExternally, isTrue);
      },
    );

    test('non-office types are unaffected by platform', () {
      const androidEngine = CapabilityEngine(
        platformInfo: _FakePlatformInfo(isIOS: false),
      );
      final caps = androidEngine.derive(
        build(type: AttachmentType.pdf, status: AttachmentStatus.ready),
      );
      expect(caps.canPreview, isTrue);
    });
  });
}
