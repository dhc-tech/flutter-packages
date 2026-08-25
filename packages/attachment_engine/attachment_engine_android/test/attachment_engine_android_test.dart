// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_android/attachment_engine_android.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachmentEngineAndroid.openOfficePreview', () {
    // openOfficePreview() falls back to openExternally() at the Dart layer
    // (Android has no in-app Office viewer), so mock openExternally()'s
    // Pigeon-generated `BasicMessageChannel` rather than a hand-written
    // `MethodChannel`.
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.attachment_engine_platform_interface.OpenHostApi.openExternally',
      OpenHostApi.pigeonChannelCodec,
    );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (message) async {
            expect(message, ['/tmp/f.docx', null]);
            return <Object?>[
              NativeOpenResultMessage(success: true, message: null),
            ];
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, null);
    });

    test('gracefully degrades to openExternally instead of throwing', () async {
      final platform = AttachmentEngineAndroid();
      await expectLater(platform.openOfficePreview('/tmp/f.docx'), completes);
    });
  });
}
