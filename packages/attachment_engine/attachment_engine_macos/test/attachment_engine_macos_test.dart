// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_macos/attachment_engine_macos.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith sets the platform instance', () {
    AttachmentEngineMacos.registerWith();
    expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineMacos>());
  });

  group('AttachmentEngineMacos', () {
    final platform = AttachmentEngineMacos();

    // Every request/response call now goes through a Pigeon-generated
    // `BasicMessageChannel` rather than a hand-written `MethodChannel` — mock
    // it with `setMockDecodedMessageHandler` using the Api's own codec so the
    // encoding stays in lockstep with `messages.g.dart`.
    void mockPigeonChannel<T>(
      String apiName,
      String methodName,
      MessageCodec<Object?> codec,
      Future<Object?> Function(List<Object?> args) handler,
    ) {
      final channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.attachment_engine_platform_interface.$apiName.$methodName',
        codec,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (message) async {
            // Pigeon sends `null` (rather than an empty list) for
            // zero-argument calls, e.g. getApplicationSupportDirectory().
            final result = await handler((message as List<Object?>?) ?? []);
            return <Object?>[result];
          });
    }

    void clearPigeonChannel(
      String apiName,
      String methodName,
      MessageCodec<Object?> codec,
    ) {
      final channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.attachment_engine_platform_interface.$apiName.$methodName',
        codec,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, null);
    }

    tearDown(() {
      clearPigeonChannel(
        'ShareHostApi',
        'shareText',
        ShareHostApi.pigeonChannelCodec,
      );
      clearPigeonChannel(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
      );
      clearPigeonChannel(
        'OfficeHostApi',
        'openOfficePreview',
        OfficeHostApi.pigeonChannelCodec,
      );
      clearPigeonChannel(
        'PathsHostApi',
        'getApplicationSupportDirectory',
        PathsHostApi.pigeonChannelCodec,
      );
    });

    test('openOfficePreview invokes the QuickLook Pigeon HostApi', () async {
      mockPigeonChannel(
        'OfficeHostApi',
        'openOfficePreview',
        OfficeHostApi.pigeonChannelCodec,
        (args) async {
          expect(args, ['/tmp/f.docx']);
          return null;
        },
      );
      await expectLater(platform.openOfficePreview('/tmp/f.docx'), completes);
    });

    test('openExternally maps the native result', () async {
      mockPigeonChannel(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
        (args) async => NativeOpenResultMessage(success: true, message: null),
      );
      final result = await platform.openExternally('/tmp/f.pdf');
      expect(result.success, isTrue);
    });

    test('getApplicationSupportDirectory returns the native path', () async {
      mockPigeonChannel(
        'PathsHostApi',
        'getApplicationSupportDirectory',
        PathsHostApi.pigeonChannelCodec,
        (args) async => '/tmp/support',
      );
      expect(await platform.getApplicationSupportDirectory(), '/tmp/support');
    });

    test(
      'shareText invokes the NSSharingServicePicker Pigeon HostApi',
      () async {
        mockPigeonChannel(
          'ShareHostApi',
          'shareText',
          ShareHostApi.pigeonChannelCodec,
          (args) async {
            expect(args, ['hello']);
            return null;
          },
        );
        await expectLater(platform.shareText('hello'), completes);
      },
    );
  });
}
