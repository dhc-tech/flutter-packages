// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:attachment_engine_linux/attachment_engine_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
              return '/tmp/attachment_engine_test/support';
            case 'getApplicationCacheDirectory':
              return '/tmp/attachment_engine_test/cache';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('registerWith sets the platform instance', () {
    AttachmentEngineLinux.registerWith();
    expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineLinux>());
  });

  test(
    'paths delegate to path_provider (flutter.dev-published, official)',
    () async {
      final impl = AttachmentEngineLinux();
      final support = await impl.getApplicationSupportDirectory();
      final cache = await impl.getApplicationCacheDirectory();
      expect(support, '/tmp/attachment_engine_test/support');
      expect(cache, '/tmp/attachment_engine_test/cache');
    },
  );

  test('shareFile is not yet implemented', () {
    final impl = AttachmentEngineLinux();
    expect(() => impl.shareFile('x'), throwsUnimplementedError);
  });

  test('audioLoad invokes the native audio channel', () async {
    const audioChannel = MethodChannel('attachment_engine/audio');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audioChannel, null),
    );

    final impl = AttachmentEngineLinux();
    await impl.audioLoad('p1', url: 'https://example.com/a.mp3');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'load');
    expect(calls.single.arguments, {
      'playerId': 'p1',
      'url': 'https://example.com/a.mp3',
    });
  });

  test('videoLoad invokes the native video channel', () async {
    const videoChannel = MethodChannel('attachment_engine/video');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(videoChannel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(videoChannel, null),
    );

    final impl = AttachmentEngineLinux();
    await impl.videoLoad('p1', filePath: '/tmp/a.mp4');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'load');
    expect(calls.single.arguments, {'playerId': 'p1', 'path': '/tmp/a.mp4'});
  });

  test('videoBuildView returns a widget without throwing', () {
    final impl = AttachmentEngineLinux();
    expect(impl.videoBuildView('p1'), isA<Widget>());
  });
}
