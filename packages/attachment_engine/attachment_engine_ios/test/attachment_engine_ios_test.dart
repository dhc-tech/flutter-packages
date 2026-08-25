import 'package:attachment_engine_ios/attachment_engine_ios.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachmentEngineIOS.openOfficePreview', () {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.attachment_engine_platform_interface.OfficeHostApi.openOfficePreview',
      OfficeHostApi.pigeonChannelCodec,
    );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (message) async {
            expect(message, ['/tmp/f.docx']);
            return <Object?>[null];
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, null);
    });

    test('invokes the QuickLook Pigeon HostApi without throwing', () async {
      final platform = AttachmentEngineIOS();
      await expectLater(platform.openOfficePreview('/tmp/f.docx'), completes);
    });
  });
}
