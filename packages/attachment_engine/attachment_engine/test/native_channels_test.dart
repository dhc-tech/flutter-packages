// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/native/native_office_channel.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every call and exposes controllable event streams, so every
/// native channel wrapper can be exercised without a real platform.
class _FakePlatform extends AttachmentEnginePlatform {
  final List<String> calls = [];
  final events = <String, StreamController<Map<Object?, Object?>>>{};
  final downloadController =
      StreamController<Map<Object?, Object?>>.broadcast();

  Object? failLoad;
  Object? failSupportDir;
  Object? failCacheDir;
  int supportDirCalls = 0;
  int cacheDirCalls = 0;
  String supportDir = '/support';
  String cacheDir = '/cache';
  int downloadCounter = 0;
  final List<String> startedUrls = [];
  final List<String> resumedUrls = [];
  final List<String> cancelled = [];
  final List<String> destPaths = [];

  StreamController<Map<Object?, Object?>> _ctl(String key) =>
      events.putIfAbsent(
        key,
        () => StreamController<Map<Object?, Object?>>.broadcast(),
      );

  void emit(String playerId, Map<Object?, Object?> event) =>
      _ctl('video:$playerId').add(event);

  @override
  Stream<Map<Object?, Object?>> videoEvents(String playerId) =>
      _ctl('video:$playerId').stream;

  @override
  Future<void> videoLoad(
    String playerId, {
    String? filePath,
    String? url,
  }) async {
    calls.add('videoLoad:$playerId:${filePath ?? url}');
    if (failLoad != null) throw failLoad!;
  }

  @override
  Future<void> videoPlay(String playerId) async => calls.add('play:$playerId');

  @override
  Future<void> videoPause(String playerId) async =>
      calls.add('pause:$playerId');

  @override
  Future<void> videoSeek(String playerId, Duration position) async =>
      calls.add('seek:$playerId:${position.inMilliseconds}');

  @override
  Future<void> videoSetSpeed(String playerId, double speed) async =>
      calls.add('speed:$playerId:$speed');

  @override
  Future<void> videoSetVolume(String playerId, double volume) async =>
      calls.add('volume:$playerId:$volume');

  @override
  Future<void> videoDispose(String playerId) async =>
      calls.add('dispose:$playerId');

  @override
  Widget videoBuildView(String playerId) => Text('view:$playerId');

  @override
  Future<void> shareFile(String path, {String? text}) async =>
      calls.add('shareFile:$path:$text');

  @override
  Future<void> shareText(String text) async => calls.add('shareText:$text');

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    calls.add('open:$path:$mimeType');
    return const NativeOpenResult(success: true);
  }

  @override
  Future<void> openOfficePreview(String path) async =>
      calls.add('office:$path');

  @override
  Future<String> getApplicationSupportDirectory() async {
    supportDirCalls++;
    if (failSupportDir != null) throw failSupportDir!;
    return supportDir;
  }

  @override
  Future<String> getApplicationCacheDirectory() async {
    cacheDirCalls++;
    if (failCacheDir != null) throw failCacheDir!;
    return cacheDir;
  }

  @override
  Stream<Map<Object?, Object?>> downloadEvents() => downloadController.stream;

  @override
  Future<String> startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) async {
    startedUrls.add(url);
    destPaths.add(destPath);
    return 'dl-${++downloadCounter}';
  }

  @override
  Future<String> resumeDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) async {
    resumedUrls.add(url);
    destPaths.add(destPath);
    return 'dl-${++downloadCounter}';
  }

  @override
  Future<void> cancelDownload(String downloadId) async =>
      cancelled.add(downloadId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    AttachmentEnginePlatform.instance = platform;
    NativePathsChannel.resetForTesting();
  });

  tearDown(() async {
    NativePathsChannel.resetForTesting();
    await platform.downloadController.close();
    for (final c in platform.events.values) {
      await c.close();
    }
  });

  group('NativeShareChannel / NativeOpenChannel / NativeOfficeChannel', () {
    test('shareFile forwards path and optional text', () async {
      await NativeShareChannel.shareFile('/a.pdf', text: 'hi');
      await NativeShareChannel.shareFile('/b.pdf');
      expect(platform.calls, ['shareFile:/a.pdf:hi', 'shareFile:/b.pdf:null']);
    });

    test('shareText forwards empty and unicode text untouched', () async {
      await NativeShareChannel.shareText('');
      await NativeShareChannel.shareText('héllo ✓');
      expect(platform.calls, ['shareText:', 'shareText:héllo ✓']);
    });

    test(
      'openExternally forwards the mime type and returns the result',
      () async {
        final r = await NativeOpenChannel.openExternally(
          '/x.docx',
          mimeType: 'application/msword',
        );
        expect(r.success, isTrue);
        await NativeOpenChannel.openExternally('/y');
        expect(platform.calls, [
          'open:/x.docx:application/msword',
          'open:/y:null',
        ]);
      },
    );

    test('openOfficePreview forwards the path', () async {
      await NativeOfficeChannel.openOfficePreview('/z.pptx');
      expect(platform.calls, ['office:/z.pptx']);
    });

    test('platform errors propagate to the caller', () async {
      AttachmentEnginePlatform.instance = _ThrowingPlatform();
      await expectLater(
        NativeShareChannel.shareText('x'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        NativeOpenChannel.openExternally('/x'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        NativeOfficeChannel.openOfficePreview('/x'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('NativePathsChannel', () {
    test('returns the platform directories and caches them', () async {
      final support = await NativePathsChannel.applicationSupportDirectory();
      final cache = await NativePathsChannel.applicationCacheDirectory();
      expect(support.path, '/support');
      expect(cache.path, '/cache');
      expect(
        identical(
          support,
          await NativePathsChannel.applicationSupportDirectory(),
        ),
        isTrue,
      );
      await NativePathsChannel.applicationCacheDirectory();
      expect(platform.supportDirCalls, 1);
      expect(platform.cacheDirCalls, 1);
    });

    test('falls back to a system-temp directory when the platform fails, and '
        'caches the fallback', () async {
      platform.failSupportDir = UnimplementedError();
      platform.failCacheDir = StateError('no platform');
      final support = await NativePathsChannel.applicationSupportDirectory();
      final cache = await NativePathsChannel.applicationCacheDirectory();
      expect(
        support.path,
        '${Directory.systemTemp.path}/attachment_engine_support',
      );
      expect(
        cache.path,
        '${Directory.systemTemp.path}/attachment_engine_cache',
      );
      await NativePathsChannel.applicationSupportDirectory();
      expect(platform.supportDirCalls, 1);
    });

    test('resetForTesting clears the cached directories', () async {
      await NativePathsChannel.applicationSupportDirectory();
      NativePathsChannel.resetForTesting();
      platform.supportDir = '/other';
      expect(
        (await NativePathsChannel.applicationSupportDirectory()).path,
        '/other',
      );
    });
  });

  group('NativeVideoController', () {
    late NativeVideoController controller;

    setUp(() => controller = NativeVideoController());

    tearDown(() async => controller.dispose());

    test('player ids are unique and numeric', () {
      final other = NativeVideoController();
      addTearDown(other.dispose);
      expect(other.playerId, isNot(controller.playerId));
      expect(int.tryParse(controller.playerId), isNotNull);
    });

    test('starts idle with a 16:9 aspect ratio and is not playing', () {
      expect(controller.status.state, NativePlaybackState.idle);
      expect(controller.status.position, Duration.zero);
      expect(controller.status.duration, isNull);
      expect(controller.isPlaying, isFalse);
      expect(controller.aspectRatio, closeTo(16 / 9, 1e-9));
    });

    test('load forwards file path or url and subscribes to events', () async {
      await controller.load(filePath: '/v.mp4');
      expect(platform.calls, ['videoLoad:${controller.playerId}:/v.mp4']);
      expect(
        platform.events.containsKey('video:${controller.playerId}'),
        isTrue,
      );
    });

    test(
      'load subscribes even when the native load fails, then rethrows',
      () async {
        platform.failLoad = StateError('native load failed');
        await expectLater(
          controller.load(url: 'https://x/v.mp4'),
          throwsA(isA<StateError>()),
        );
        final seen = <NativePlaybackStatus>[];
        final sub = controller.statusStream.listen(seen.add);
        addTearDown(sub.cancel);
        platform.emit(controller.playerId, {'state': 'error'});
        await pumpEventQueue();
        expect(seen.single.state, NativePlaybackState.error);
      },
    );

    test('a second load does not subscribe twice', () async {
      await controller.load(filePath: '/a');
      await controller.load(filePath: '/b');
      final seen = <NativePlaybackStatus>[];
      final sub = controller.statusStream.listen(seen.add);
      addTearDown(sub.cancel);
      platform.emit(controller.playerId, {'state': 'ready'});
      await pumpEventQueue();
      expect(seen, hasLength(1));
    });

    test('events update state, position, duration and aspect ratio', () async {
      await controller.load(filePath: '/v.mp4');
      platform.emit(controller.playerId, {
        'state': 'playing',
        'positionMs': 1500,
        'durationMs': 60000,
        'width': 1080,
        'height': 1920,
      });
      await pumpEventQueue();
      expect(controller.status.state, NativePlaybackState.playing);
      expect(controller.isPlaying, isTrue);
      expect(controller.status.position, const Duration(milliseconds: 1500));
      expect(controller.status.duration, const Duration(minutes: 1));
      expect(controller.aspectRatio, closeTo(1080 / 1920, 1e-9));
    });

    test(
      'partial, unknown or malformed events keep the previous values',
      () async {
        await controller.load(filePath: '/v.mp4');
        platform.emit(controller.playerId, {
          'state': 'paused',
          'positionMs': 10,
          'durationMs': 100,
          'width': 400,
          'height': 200,
        });
        await pumpEventQueue();
        platform.emit(controller.playerId, {'state': 'not-a-state'});
        platform.emit(controller.playerId, {'width': 100, 'height': 0});
        platform.emit(controller.playerId, {'width': 100});
        platform.emit(controller.playerId, {'positionMs': 20.9});
        await pumpEventQueue();
        expect(controller.status.state, NativePlaybackState.paused);
        expect(controller.status.position, const Duration(milliseconds: 20));
        expect(controller.status.duration, const Duration(milliseconds: 100));
        expect(controller.aspectRatio, closeTo(2, 1e-9));
      },
    );

    test('a stream error does not break the subscription', () async {
      await controller.load(filePath: '/v.mp4');
      final ctl = platform.events['video:${controller.playerId}']!;
      final seen = <NativePlaybackStatus>[];
      final sub = controller.statusStream.listen(seen.add);
      addTearDown(sub.cancel);
      ctl.addError(StateError('stream error'));
      platform.emit(controller.playerId, {'state': 'ready'});
      await pumpEventQueue();
      expect(seen.map((s) => s.state), [NativePlaybackState.ready]);
    });

    test(
      'transport controls forward to the platform with the player id',
      () async {
        final id = controller.playerId;
        await controller.play();
        await controller.pause();
        await controller.seek(const Duration(seconds: 3));
        await controller.setSpeed(1.5);
        await controller.setVolume(0);
        expect(platform.calls, [
          'play:$id',
          'pause:$id',
          'seek:$id:3000',
          'speed:$id:1.5',
          'volume:$id:0.0',
        ]);
      },
    );

    test('buildView asks the platform for the player surface', () {
      final w = controller.buildView() as Text;
      expect(w.data, 'view:${controller.playerId}');
    });

    test('dispose cancels the subscription, closes the status stream and '
        'releases the native player', () async {
      await controller.load(filePath: '/v.mp4');
      var done = false;
      controller.statusStream.listen((_) {}, onDone: () => done = true);
      await controller.dispose();
      await pumpEventQueue();
      expect(done, isTrue);
      expect(platform.calls.last, 'dispose:${controller.playerId}');
      // Re-created in tearDown for symmetry: a second dispose must not
      // leave the next test's controller affected.
      controller = NativeVideoController();
    });

    test('dispose without a prior load is safe', () async {
      final fresh = NativeVideoController();
      await fresh.dispose();
      expect(platform.calls, contains('dispose:${fresh.playerId}'));
    });
  });

  group('NativePlaybackStatus', () {
    test('initial status is idle at zero with unknown duration', () {
      final s = NativePlaybackStatus.initial();
      expect(s.state, NativePlaybackState.idle);
      expect(s.position, Duration.zero);
      expect(s.duration, isNull);
    });
  });

  group('NativeDownloadClient', () {
    late Directory tempDir;
    late NativeDownloadClient client;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('native_dl_test');
      client = NativeDownloadClient(tempDirPath: tempDir.path);
    });

    tearDown(() {
      client.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test(
      'completes with the file bytes named by the completed event',
      () async {
        final file = File('${tempDir.path}/out.bin')
          ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
        final future = client.download('https://x/f');
        await pumpEventQueue();
        platform.downloadController.add({
          'downloadId': 'dl-1',
          'type': 'completed',
          'path': file.path,
        });
        expect(await future, Uint8List.fromList([1, 2, 3, 4]));
      },
    );

    test('falls back to the destination path when the completed event has no '
        'path', () async {
      final future = client.download(
        'https://x/f',
        destinationHint: 'hint.bin',
      );
      await pumpEventQueue();
      File(platform.destPaths.single).writeAsBytesSync([9, 9]);
      platform.downloadController.add({
        'downloadId': 'dl-1',
        'type': 'completed',
      });
      expect(await future, Uint8List.fromList([9, 9]));
    });

    test(
      'a completed event pointing at a missing file fails the download',
      () async {
        final future = client.download('https://x/f');
        final expectation = expectLater(
          future,
          throwsA(isA<FileSystemException>()),
        );
        await pumpEventQueue();
        platform.downloadController.add({
          'downloadId': 'dl-1',
          'type': 'completed',
          'path': '${tempDir.path}/nope',
        });
        await expectation;
      },
    );

    test('an empty downloaded file yields an empty byte list', () async {
      final file = File('${tempDir.path}/empty')..writeAsBytesSync([]);
      final future = client.download('https://x/f');
      await pumpEventQueue();
      platform.downloadController.add({
        'downloadId': 'dl-1',
        'type': 'completed',
        'path': file.path,
      });
      expect(await future, isEmpty);
    });

    test(
      'an error event fails the download with its message, or a default',
      () async {
        final first = client.download('https://x/1');
        final firstExpectation = expectLater(
          first,
          throwsA(
            predicate(
              (e) => e is Exception && e.toString().contains('disk full'),
            ),
          ),
        );
        await pumpEventQueue();
        platform.downloadController.add({
          'downloadId': 'dl-1',
          'type': 'error',
          'message': 'disk full',
        });
        await firstExpectation;

        final second = client.download('https://x/2');
        final secondExpectation = expectLater(
          second,
          throwsA(predicate((e) => e.toString().contains('Download failed'))),
        );
        await pumpEventQueue();
        platform.downloadController.add({
          'downloadId': 'dl-2',
          'type': 'error',
        });
        await secondExpectation;
      },
    );

    test(
      'progress events reach onProgress; negative/absent totals are unknown',
      () async {
        final progress = <DownloadProgress>[];
        final file = File('${tempDir.path}/f')..writeAsBytesSync([1]);
        final future = client.download('https://x/f', onProgress: progress.add);
        await pumpEventQueue();
        platform.downloadController
          ..add({
            'downloadId': 'dl-1',
            'type': 'progress',
            'received': 10,
            'total': 100,
          })
          ..add({
            'downloadId': 'dl-1',
            'type': 'progress',
            'received': 20,
            'total': -1,
          })
          ..add({'downloadId': 'dl-1', 'type': 'progress', 'received': 30})
          ..add({'downloadId': 'dl-1', 'type': 'progress'});
        await pumpEventQueue();
        platform.downloadController.add({
          'downloadId': 'dl-1',
          'type': 'completed',
          'path': file.path,
        });
        await future;
        expect(progress.map((p) => (p.received, p.total)), [
          (10, 100),
          (20, null),
          (30, null),
          (0, null),
        ]);
      },
    );

    test('incomplete events and events for unknown ids are ignored', () async {
      final future = client.download('https://x/f');
      await pumpEventQueue();
      platform.downloadController
        ..add({'type': 'completed'})
        ..add({'downloadId': 'someone-else', 'type': 'error'})
        ..add({'downloadId': 'dl-1', 'type': 'mystery'})
        ..add({'downloadId': 'dl-1'});
      platform.downloadController.addError(StateError('stream err'));
      await pumpEventQueue();
      final file = File('${tempDir.path}/f')..writeAsBytesSync([5]);
      platform.downloadController.add({
        'downloadId': 'dl-1',
        'type': 'completed',
        'path': file.path,
      });
      expect(await future, Uint8List.fromList([5]));
    });

    test('resume uses resumeDownload instead of startDownload', () async {
      final file = File('${tempDir.path}/f')..writeAsBytesSync([1]);
      final future = client.download('https://x/f', resume: true);
      await pumpEventQueue();
      platform.downloadController.add({
        'downloadId': 'dl-1',
        'type': 'completed',
        'path': file.path,
      });
      await future;
      expect(platform.resumedUrls, ['https://x/f']);
      expect(platform.startedUrls, isEmpty);
    });

    test('concurrent downloads are demultiplexed by id', () async {
      final a = File('${tempDir.path}/a')..writeAsBytesSync([1]);
      final b = File('${tempDir.path}/b')..writeAsBytesSync([2]);
      final fa = client.download('https://x/a');
      final fb = client.download('https://x/b');
      await pumpEventQueue();
      platform.downloadController
        ..add({'downloadId': 'dl-2', 'type': 'completed', 'path': b.path})
        ..add({'downloadId': 'dl-1', 'type': 'completed', 'path': a.path});
      expect(await fa, Uint8List.fromList([1]));
      expect(await fb, Uint8List.fromList([2]));
    });

    test('cancel before the download id is known, or with a foreign token, is '
        'a no-op', () async {
      final token = client.createCancelToken();
      client.cancel(token);
      client.cancel(Object());
      client.cancel('not a token');
      expect(platform.cancelled, isEmpty);
    });

    test('cancelling mid-flight forwards the id to the platform', () async {
      final token = client.createCancelToken();
      final future = client.download('https://x/f', cancelToken: token);
      final expectation = expectLater(
        future,
        throwsA(isA<DownloadCancelledException>()),
      );
      await pumpEventQueue();
      client.cancel(token);
      await expectation;
      expect(platform.cancelled, ['dl-1']);
    });

    test('dispose rejects in-flight downloads and is idempotent', () async {
      final future = client.download('https://x/f');
      final expectation = expectLater(
        future,
        throwsA(isA<DownloadCancelledException>()),
      );
      await pumpEventQueue();
      client.dispose();
      client.dispose();
      await expectation;
    });

    test('events after dispose are not delivered', () async {
      client.dispose();
      final progress = <DownloadProgress>[];
      platform.downloadController.add({
        'downloadId': 'dl-1',
        'type': 'progress',
        'received': 1,
      });
      await pumpEventQueue();
      expect(progress, isEmpty);
    });

    test('destination paths are sanitised, bounded and deterministic for a '
        'hint', () {
      expect(
        client.destPathForTesting('a b/c?d=e'),
        '${tempDir.path}/attachment_engine_dl_a_b_c_d_e',
      );
      expect(
        client.destPathForTesting('x' * 500).length,
        tempDir.path.length + '/attachment_engine_dl_'.length + 120,
      );
      expect(client.destPathForTesting('h'), client.destPathForTesting('h'));
      expect(
        client.destPathForTesting(''),
        startsWith('${tempDir.path}/attachment_engine_dl_'),
      );
      expect(client.destPathForTesting('..'), endsWith('_'));
      expect(client.destPathForTesting('日本語'), endsWith('___'));
    });

    test('the default temp directory is the system temp directory', () {
      final c = NativeDownloadClient();
      addTearDown(c.dispose);
      expect(c.destPathForTesting('x'), startsWith(Directory.systemTemp.path));
    });
  });
}

class _ThrowingPlatform extends AttachmentEnginePlatform {
  @override
  Future<void> shareText(String text) => Future.error(StateError('x'));

  @override
  Future<NativeOpenResult> openExternally(String path, {String? mimeType}) =>
      Future.error(StateError('x'));

  @override
  Future<void> openOfficePreview(String path) => Future.error(StateError('x'));
}
