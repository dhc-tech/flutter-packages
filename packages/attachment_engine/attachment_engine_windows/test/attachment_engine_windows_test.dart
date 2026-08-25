import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:attachment_engine_windows/attachment_engine_windows.dart';
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
    AttachmentEngineWindows.registerWith();
    expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineWindows>());
  });

  test(
    'paths delegate to path_provider (flutter.dev-published, official)',
    () async {
      final impl = AttachmentEngineWindows();
      final support = await impl.getApplicationSupportDirectory();
      final cache = await impl.getApplicationCacheDirectory();
      expect(support, '/tmp/attachment_engine_test/support');
      expect(cache, '/tmp/attachment_engine_test/cache');
    },
  );

  test('shareFile invokes the native share channel', () async {
    const shareChannel = MethodChannel('attachment_engine/share');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    final impl = AttachmentEngineWindows();
    await impl.shareFile('C:\\a.txt', text: 'hello');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'shareFile');
    expect(calls.single.arguments, {'path': 'C:\\a.txt', 'text': 'hello'});
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

    final impl = AttachmentEngineWindows();
    await impl.audioLoad('p1', url: 'https://example.com/a.mp3');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'load');
    expect(calls.single.arguments, {
      'playerId': 'p1',
      'url': 'https://example.com/a.mp3',
    });
  });

  test('videoBuildView returns a widget without throwing', () {
    final impl = AttachmentEngineWindows();
    expect(impl.videoBuildView('p1'), isA<Widget>());
  });
}
