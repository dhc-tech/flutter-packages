// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends AttachmentEnginePlatform {}

// Implements rather than extends, so it carries no valid verification token.
class _ImplementsPlatform implements AttachmentEnginePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockedPlatform extends _FakePlatform with MockPlatformInterfaceMixin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachmentEnginePlatform.instance', () {
    late AttachmentEnginePlatform original;

    setUp(() => original = AttachmentEnginePlatform.instance);
    tearDown(() => AttachmentEnginePlatform.instance = original);

    test('default instance throws UnimplementedError', () {
      expect(
        () =>
            AttachmentEnginePlatform.instance.getApplicationSupportDirectory(),
        throwsUnimplementedError,
      );
    });

    test('can be overridden by a subclass that extends the interface', () {
      final fake = _FakePlatform();
      AttachmentEnginePlatform.instance = fake;
      expect(AttachmentEnginePlatform.instance, same(fake));
    });

    test('accepts a mock that opts out of verification', () {
      final mock = _MockedPlatform();
      AttachmentEnginePlatform.instance = mock;
      expect(AttachmentEnginePlatform.instance, same(mock));
    });

    test('rejects an implementation that only implements the interface', () {
      expect(
        () => AttachmentEnginePlatform.instance = _ImplementsPlatform(),
        throwsA(anything),
      );
      expect(AttachmentEnginePlatform.instance, same(original));
    });
  });

  group('default method bodies throw UnimplementedError', () {
    final platform = _FakePlatform();
    final calls = <String, Object? Function()>{
      'pdfOpen': () => platform.pdfOpen('x'),
      'pdfRenderPage': () =>
          platform.pdfRenderPage('h', 0, width: 1, height: 1),
      'pdfClose': () => platform.pdfClose('h'),
      'audioLoad': () => platform.audioLoad('p', url: 'u'),
      'audioPlay': () => platform.audioPlay('p'),
      'audioPause': () => platform.audioPause('p'),
      'audioSeek': () => platform.audioSeek('p', Duration.zero),
      'audioSetSpeed': () => platform.audioSetSpeed('p', 1),
      'audioSetVolume': () => platform.audioSetVolume('p', 1),
      'audioDispose': () => platform.audioDispose('p'),
      'audioEvents': () => platform.audioEvents('p'),
      'videoLoad': () => platform.videoLoad('p', url: 'u'),
      'videoPlay': () => platform.videoPlay('p'),
      'videoPause': () => platform.videoPause('p'),
      'videoSeek': () => platform.videoSeek('p', Duration.zero),
      'videoSetSpeed': () => platform.videoSetSpeed('p', 1),
      'videoSetVolume': () => platform.videoSetVolume('p', 1),
      'videoDispose': () => platform.videoDispose('p'),
      'videoEvents': () => platform.videoEvents('p'),
      'videoBuildView': () => platform.videoBuildView('p'),
      'shareFile': () => platform.shareFile('x'),
      'shareText': () => platform.shareText('x'),
      'openExternally': () => platform.openExternally('x'),
      'openOfficePreview': () => platform.openOfficePreview('x'),
      'getApplicationSupportDirectory': () =>
          platform.getApplicationSupportDirectory(),
      'getApplicationCacheDirectory': () =>
          platform.getApplicationCacheDirectory(),
      'startDownload': () => platform.startDownload('u', const {}, 'd'),
      'resumeDownload': () => platform.resumeDownload('u', const {}, 'd'),
      'cancelDownload': () => platform.cancelDownload('id'),
      'downloadEvents': () => platform.downloadEvents(),
    };

    for (final entry in calls.entries) {
      test(entry.key, () {
        expect(
          entry.value,
          throwsA(
            isA<UnimplementedError>().having(
              (e) => e.message,
              'message',
              contains('${entry.key}() has not been implemented'),
            ),
          ),
        );
      });
    }
  });

  group('value types', () {
    test('PdfOpenResult keeps its fields', () {
      const result = PdfOpenResult(handle: 'h', pageCount: 3);
      expect(result.handle, 'h');
      expect(result.pageCount, 3);
    });

    test('NativeOpenResult message defaults to null', () {
      const ok = NativeOpenResult(success: true);
      expect(ok.success, isTrue);
      expect(ok.message, isNull);
      const failed = NativeOpenResult(success: false, message: 'nope');
      expect(failed.message, 'nope');
    });
  });

  group('PdfOpenResultMessage', () {
    test('encode/decode round trips', () {
      final message = PdfOpenResultMessage(handle: 'h', pageCount: 9);
      final decoded = PdfOpenResultMessage.decode(message.encode());
      expect(decoded, message);
      expect(decoded.handle, 'h');
      expect(decoded.pageCount, 9);
    });

    test('equality, hashCode and toString are value based', () {
      final a = PdfOpenResultMessage(handle: 'h', pageCount: 1);
      final b = PdfOpenResultMessage(handle: 'h', pageCount: 1);
      final c = PdfOpenResultMessage(handle: 'h', pageCount: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a == Object(), isFalse);
      expect(a.toString(), 'PdfOpenResultMessage(handle: h, pageCount: 1)');
    });
  });

  group('NativeOpenResultMessage', () {
    test('encode/decode round trips with and without message', () {
      final withMessage = NativeOpenResultMessage(success: false, message: 'm');
      expect(NativeOpenResultMessage.decode(withMessage.encode()), withMessage);
      final bare = NativeOpenResultMessage(success: true);
      final decoded = NativeOpenResultMessage.decode(bare.encode());
      expect(decoded.success, isTrue);
      expect(decoded.message, isNull);
    });

    test('equality, hashCode and toString are value based', () {
      final a = NativeOpenResultMessage(success: true, message: 'x');
      final b = NativeOpenResultMessage(success: true, message: 'x');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(NativeOpenResultMessage(success: true)));
      expect(a, isNot(NativeOpenResultMessage(success: false, message: 'x')));
      expect(
        a.toString(),
        'NativeOpenResultMessage(success: true, message: x)',
      );
    });
  });

  group('Pigeon codec', () {
    test('serializes both message classes and ints through the codec', () {
      const codec = PdfHostApi.pigeonChannelCodec;
      final pdf = PdfOpenResultMessage(handle: 'h', pageCount: 1 << 40);
      final open = NativeOpenResultMessage(success: true, message: 'm');
      final decoded = codec.decodeMessage(
        codec.encodeMessage(<Object?>[pdf, open, 1 << 40, 'str']),
      );
      expect(decoded, <Object?>[pdf, open, 1 << 40, 'str']);
    });
  });

  group('HostApi message channel suffix', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    test('suffix is appended to the channel name', () async {
      const name =
          'dev.flutter.pigeon.attachment_engine_platform_interface.PdfHostApi.renderPage.s1';
      final channel = BasicMessageChannel<Object?>(
        name,
        PdfHostApi.pigeonChannelCodec,
      );
      messenger.setMockDecodedMessageHandler<Object?>(
        channel,
        (message) async => <Object?>[
          Uint8List.fromList([1, 2]),
        ],
      );
      addTearDown(
        () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
      );
      final api = PdfHostApi(messageChannelSuffix: 's1');
      expect(api.pigeonVar_messageChannelSuffix, '.s1');
      expect(await api.renderPage('h', 0, 1, 1), Uint8List.fromList([1, 2]));
      expect(PdfHostApi().pigeonVar_messageChannelSuffix, isEmpty);
    });
  });
}
