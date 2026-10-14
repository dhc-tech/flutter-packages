// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine_macos/attachment_engine_macos.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String _prefix =
    'dev.flutter.pigeon.attachment_engine_platform_interface';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final registered = <BasicMessageChannel<Object?>>[];
  final MethodCodec methodCodec = const StandardMethodCodec();

  /// Mocks a Pigeon channel and records the arguments received. The handler's
  /// return value is wrapped in the single-element success envelope Pigeon
  /// expects; return a raw reply list via [mockRawReply] for failures.
  List<Object?> mockPigeon(
    String api,
    String method,
    MessageCodec<Object?> codec,
    Object? result,
  ) {
    final received = <Object?>[];
    final channel = BasicMessageChannel<Object?>(
      '$_prefix.$api.$method',
      codec,
    );
    registered.add(channel);
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      received.add(message);
      return <Object?>[result];
    });
    return received;
  }

  void mockRawReply(
    String api,
    String method,
    MessageCodec<Object?> codec,
    List<Object?> reply,
  ) {
    final channel = BasicMessageChannel<Object?>(
      '$_prefix.$api.$method',
      codec,
    );
    registered.add(channel);
    messenger.setMockDecodedMessageHandler<Object?>(
      channel,
      (message) async => reply,
    );
  }

  tearDown(() {
    for (final channel in registered) {
      messenger.setMockDecodedMessageHandler<Object?>(channel, null);
    }
    registered.clear();
    for (final name in [
      'attachment_engine/download_events',
      'attachment_engine/audio_events/p1',
      'attachment_engine/video_events/p1',
    ]) {
      messenger.setMockMessageHandler(name, null);
    }
  });

  final platform = AttachmentEngineMacos();

  test('registerWith installs the implementation as the platform instance', () {
    AttachmentEngineMacos.registerWith();
    expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineMacos>());
  });

  group('edge cases', () {
    test(
      'empty, whitespace and very long strings pass through unchanged',
      () async {
        final long = 'a' * 100000;
        final received = mockPigeon(
          'ShareHostApi',
          'shareText',
          ShareHostApi.pigeonChannelCodec,
          null,
        );
        await platform.shareText('');
        await platform.shareText('  \n\t ');
        await platform.shareText(long);
        await platform.shareText('emoji \u{1F600} \u00e9 \u4e2d');
        expect(received, [
          [''],
          ['  \n\t '],
          [long],
          ['emoji \u{1F600} \u00e9 \u4e2d'],
        ]);
      },
    );

    test('empty paths are forwarded, not rejected locally', () async {
      final received = mockPigeon(
        'PdfHostApi',
        'open',
        PdfHostApi.pigeonChannelCodec,
        PdfOpenResultMessage(handle: '', pageCount: 0),
      );
      final result = await platform.pdfOpen('');
      expect(received.single, ['']);
      expect(result.handle, isEmpty);
      expect(result.pageCount, 0);
    });

    test('seek boundary values: zero, negative and very large', () async {
      final received = mockPigeon(
        'AudioHostApi',
        'seek',
        AudioHostApi.pigeonChannelCodec,
        null,
      );
      await platform.audioSeek('p1', Duration.zero);
      await platform.audioSeek('p1', const Duration(milliseconds: -1));
      await platform.audioSeek('p1', const Duration(days: 365 * 100));
      await platform.audioSeek('p1', const Duration(microseconds: 999));
      expect(received, [
        ['p1', 0],
        ['p1', -1],
        ['p1', const Duration(days: 365 * 100).inMilliseconds],
        ['p1', 0],
      ]);
    });

    test('speed and volume boundary values survive the codec', () async {
      final speed = mockPigeon(
        'VideoHostApi',
        'setSpeed',
        VideoHostApi.pigeonChannelCodec,
        null,
      );
      final volume = mockPigeon(
        'VideoHostApi',
        'setVolume',
        VideoHostApi.pigeonChannelCodec,
        null,
      );
      await platform.videoSetSpeed('p1', 0);
      await platform.videoSetSpeed('p1', -1);
      await platform.videoSetSpeed('p1', double.infinity);
      await platform.videoSetVolume('p1', 0);
      await platform.videoSetVolume('p1', 1);
      await platform.videoSetVolume('p1', double.nan);
      expect(speed, [
        ['p1', 0.0],
        ['p1', -1.0],
        ['p1', double.infinity],
      ]);
      expect(volume[0], ['p1', 0.0]);
      expect(volume[1], ['p1', 1.0]);
      expect((volume[2] as List<Object?>)[1], isNaN);
    });

    test(
      'load with neither or both of filePath and url forwards as given',
      () async {
        final received = mockPigeon(
          'AudioHostApi',
          'load',
          AudioHostApi.pigeonChannelCodec,
          null,
        );
        await platform.audioLoad('p1');
        await platform.audioLoad('p1', filePath: '/f', url: 'https://x.test');
        expect(received, [
          ['p1', null, null],
          ['p1', '/f', 'https://x.test'],
        ]);
      },
    );

    test('pdfRenderPage boundary dimensions and negative index', () async {
      final received = mockPigeon(
        'PdfHostApi',
        'renderPage',
        PdfHostApi.pigeonChannelCodec,
        Uint8List(0),
      );
      final bytes = await platform.pdfRenderPage(
        'h',
        -1,
        width: 0,
        height: 1 << 31,
      );
      expect(bytes, isEmpty);
      expect(received.single, ['h', -1, 0, 1 << 31]);
    });

    test('pdfRenderPage rejects a reply of the wrong type', () {
      mockPigeon(
        'PdfHostApi',
        'renderPage',
        PdfHostApi.pigeonChannelCodec,
        'x',
      );
      expect(
        platform.pdfRenderPage('h', 0, width: 1, height: 1),
        throwsA(isA<TypeError>()),
      );
    });

    test('pdfOpen rejects a malformed message payload', () {
      mockPigeon('PdfHostApi', 'open', PdfHostApi.pigeonChannelCodec, 42);
      expect(platform.pdfOpen('/a'), throwsA(anything));
    });

    test('repeated and concurrent calls are each delivered', () async {
      final received = mockPigeon(
        'AudioHostApi',
        'play',
        AudioHostApi.pigeonChannelCodec,
        null,
      );
      await Future.wait([
        for (var i = 0; i < 20; i++) platform.audioPlay('p$i'),
      ]);
      await platform.audioPlay('p0');
      await platform.audioPlay('p0');
      expect(received, hasLength(22));
      expect(
        received.take(20).map((a) => (a! as List<Object?>).single).toSet(),
        hasLength(20),
      );
    });

    test('concurrent downloads keep their own ids', () async {
      var n = 0;
      final channel = BasicMessageChannel<Object?>(
        '$_prefix.DownloadHostApi.startDownload',
        DownloadHostApi.pigeonChannelCodec,
      );
      registered.add(channel);
      messenger.setMockDecodedMessageHandler<Object?>(
        channel,
        (message) async => <Object?>['id-${n++}'],
      );
      final ids = await Future.wait([
        platform.startDownload('u1', const {}, 'd1'),
        platform.startDownload('u2', const {}, 'd2'),
        platform.startDownload('u3', const {}, 'd3'),
      ]);
      expect(ids.toSet(), hasLength(3));
    });

    test('download headers: empty map and many entries', () async {
      final received = mockPigeon(
        'DownloadHostApi',
        'startDownload',
        DownloadHostApi.pigeonChannelCodec,
        'id',
      );
      final many = {for (var i = 0; i < 200; i++) 'h$i': 'v$i'};
      await platform.startDownload('', const {}, '');
      await platform.startDownload('u', many, 'd');
      expect(received[0], ['', <Object?, Object?>{}, '']);
      expect((received[1] as List<Object?>)[1], many);
    });

    test('cancelDownload of an unknown id surfaces the native error', () {
      mockRawReply(
        'DownloadHostApi',
        'cancelDownload',
        DownloadHostApi.pigeonChannelCodec,
        ['not-found', 'no such download', null],
      );
      expect(
        platform.cancelDownload('nope'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'not-found'),
        ),
      );
    });

    test('openExternally failure message may be null', () async {
      mockRawReply(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
        ['open-failed', null, null],
      );
      final result = await platform.openExternally('/tmp/a.pdf');
      expect(result.success, isFalse);
      expect(result.message, isNull);
    });

    test('openExternally with empty path and mimeType', () async {
      final received = mockPigeon(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
        NativeOpenResultMessage(success: true),
      );
      await platform.openExternally('', mimeType: '');
      expect(received.single, ['', '']);
    });

    test(
      'event streams: error events are forwarded and re-listen works',
      () async {
        const name = 'attachment_engine/download_events';
        var listens = 0;
        messenger.setMockMessageHandler(name, (message) async {
          final call = methodCodec.decodeMethodCall(message);
          if (call.method == 'listen') {
            listens++;
            if (listens == 1) {
              await messenger.handlePlatformMessage(
                name,
                methodCodec.encodeErrorEnvelope(code: 'E', message: 'broken'),
                (_) {},
              );
            }
            await messenger.handlePlatformMessage(
              name,
              methodCodec.encodeSuccessEnvelope({'n': listens}),
              (_) {},
            );
          }
          return methodCodec.encodeSuccessEnvelope(null);
        });
        final errors = <Object>[];
        final first = Completer<Map<Object?, Object?>>();
        final sub = platform.downloadEvents().listen(
          first.complete,
          onError: errors.add,
        );
        expect(await first.future, {'n': 1});
        expect(errors.single, isA<PlatformException>());
        await sub.cancel();
        final second = await platform.downloadEvents().first;
        expect(second, {'n': 2});
        expect(listens, 2);
      },
    );

    test(
      'cancelling an events subscription sends cancel to the platform',
      () async {
        const name = 'attachment_engine/audio_events/p1';
        final methods = <String>[];
        messenger.setMockMessageHandler(name, (message) async {
          methods.add(methodCodec.decodeMethodCall(message).method);
          return methodCodec.encodeSuccessEnvelope(null);
        });
        final sub = platform.audioEvents('p1').listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(methods, ['listen', 'cancel']);
      },
    );

    test('events for different players use separate channels', () async {
      final listened = <String>[];
      for (final id in ['p1', 'p2']) {
        messenger.setMockMessageHandler('attachment_engine/video_events/$id', (
          message,
        ) async {
          if (methodCodec.decodeMethodCall(message).method == 'listen') {
            listened.add(id);
          }
          return methodCodec.encodeSuccessEnvelope(null);
        });
      }
      final a = platform.videoEvents('p1').listen((_) {});
      final b = platform.videoEvents('p2').listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await a.cancel();
      await b.cancel();
      expect(listened, ['p1', 'p2']);
      for (final id in ['p1', 'p2']) {
        messenger.setMockMessageHandler(
          'attachment_engine/video_events/$id',
          null,
        );
      }
    });

    test('videoBuildView with an empty player id', () {
      final view = platform.videoBuildView('') as dynamic;
      expect(view.creationParams, {'playerId': ''});
    });
  });

  group('PDF', () {
    test('pdfOpen maps the native message to PdfOpenResult', () async {
      final received = mockPigeon(
        'PdfHostApi',
        'open',
        PdfHostApi.pigeonChannelCodec,
        PdfOpenResultMessage(handle: 'h1', pageCount: 7),
      );
      final result = await platform.pdfOpen('/tmp/a.pdf');
      expect(result.handle, 'h1');
      expect(result.pageCount, 7);
      expect(received.single, ['/tmp/a.pdf']);
    });

    test('pdfOpen surfaces native errors as PlatformException', () async {
      mockRawReply('PdfHostApi', 'open', PdfHostApi.pigeonChannelCodec, [
        'corrupt',
        'bad pdf',
        null,
      ]);
      await expectLater(
        platform.pdfOpen('/tmp/a.pdf'),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'corrupt')
              .having((e) => e.message, 'message', 'bad pdf'),
        ),
      );
    });

    test('pdfOpen fails with channel-error when nothing is registered', () {
      expect(
        platform.pdfOpen('/tmp/a.pdf'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'channel-error',
          ),
        ),
      );
    });

    test('pdfOpen fails with null-error on an empty native result', () {
      mockPigeon('PdfHostApi', 'open', PdfHostApi.pigeonChannelCodec, null);
      expect(
        platform.pdfOpen('/tmp/a.pdf'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'null-error'),
        ),
      );
    });

    test('pdfRenderPage passes positional and named args in order', () async {
      final png = Uint8List.fromList([137, 80, 78, 71]);
      final received = mockPigeon(
        'PdfHostApi',
        'renderPage',
        PdfHostApi.pigeonChannelCodec,
        png,
      );
      final bytes = await platform.pdfRenderPage(
        'h1',
        2,
        width: 640,
        height: 480,
      );
      expect(bytes, png);
      expect(received.single, ['h1', 2, 640, 480]);
    });

    test('pdfClose forwards the handle', () async {
      final received = mockPigeon(
        'PdfHostApi',
        'close',
        PdfHostApi.pigeonChannelCodec,
        null,
      );
      await platform.pdfClose('h1');
      expect(received.single, ['h1']);
    });
  });

  for (final kind in ['audio', 'video']) {
    final isAudio = kind == 'audio';
    final api = isAudio ? 'AudioHostApi' : 'VideoHostApi';
    final MessageCodec<Object?> codec = isAudio
        ? AudioHostApi.pigeonChannelCodec
        : VideoHostApi.pigeonChannelCodec;

    group(kind, () {
      test('load forwards filePath and null url', () async {
        final received = mockPigeon(api, 'load', codec, null);
        if (isAudio) {
          await platform.audioLoad('p1', filePath: '/tmp/a');
        } else {
          await platform.videoLoad('p1', filePath: '/tmp/a');
        }
        expect(received.single, ['p1', '/tmp/a', null]);
      });

      test('load forwards url and null filePath', () async {
        final received = mockPigeon(api, 'load', codec, null);
        if (isAudio) {
          await platform.audioLoad('p1', url: 'https://x.test/a');
        } else {
          await platform.videoLoad('p1', url: 'https://x.test/a');
        }
        expect(received.single, ['p1', null, 'https://x.test/a']);
      });

      test('play and pause forward the player id', () async {
        final play = mockPigeon(api, 'play', codec, null);
        final pause = mockPigeon(api, 'pause', codec, null);
        if (isAudio) {
          await platform.audioPlay('p1');
          await platform.audioPause('p1');
        } else {
          await platform.videoPlay('p1');
          await platform.videoPause('p1');
        }
        expect(play.single, ['p1']);
        expect(pause.single, ['p1']);
      });

      test('seek converts the Duration to milliseconds', () async {
        final received = mockPigeon(api, 'seek', codec, null);
        const position = Duration(seconds: 3, milliseconds: 250);
        if (isAudio) {
          await platform.audioSeek('p1', position);
        } else {
          await platform.videoSeek('p1', position);
        }
        expect(received.single, ['p1', 3250]);
      });

      test('setSpeed and setVolume forward doubles', () async {
        final speed = mockPigeon(api, 'setSpeed', codec, null);
        final volume = mockPigeon(api, 'setVolume', codec, null);
        if (isAudio) {
          await platform.audioSetSpeed('p1', 1.5);
          await platform.audioSetVolume('p1', 0.25);
        } else {
          await platform.videoSetSpeed('p1', 1.5);
          await platform.videoSetVolume('p1', 0.25);
        }
        expect(speed.single, ['p1', 1.5]);
        expect(volume.single, ['p1', 0.25]);
      });

      test('dispose forwards the player id', () async {
        final received = mockPigeon(api, 'dispose', codec, null);
        if (isAudio) {
          await platform.audioDispose('p1');
        } else {
          await platform.videoDispose('p1');
        }
        expect(received.single, ['p1']);
      });

      test('native failures propagate as PlatformException', () async {
        mockRawReply(api, 'play', codec, ['err', 'boom', 'details']);
        final future = isAudio
            ? platform.audioPlay('p1')
            : platform.videoPlay('p1');
        await expectLater(
          future,
          throwsA(
            isA<PlatformException>()
                .having((e) => e.code, 'code', 'err')
                .having((e) => e.details, 'details', 'details'),
          ),
        );
      });

      test('events stream yields only Map events from its channel', () async {
        final name = 'attachment_engine/${kind}_events/p1';
        messenger.setMockMessageHandler(name, (message) async {
          final call = methodCodec.decodeMethodCall(message);
          if (call.method == 'listen') {
            for (final event in <Object?>[
              {'state': 'playing', 'positionMs': 10},
              'not-a-map',
              null,
              {'state': 'paused', 'positionMs': 20},
            ]) {
              await messenger.handlePlatformMessage(
                name,
                methodCodec.encodeSuccessEnvelope(event),
                (_) {},
              );
            }
          }
          return methodCodec.encodeSuccessEnvelope(null);
        });
        final stream = isAudio
            ? platform.audioEvents('p1')
            : platform.videoEvents('p1');
        expect(await stream.take(2).toList(), [
          {'state': 'playing', 'positionMs': 10},
          {'state': 'paused', 'positionMs': 20},
        ]);
      });
    });
  }

  group('videoBuildView', () {
    test('builds a AppKitView bound to the player id', () {
      final view = platform.videoBuildView('p1') as AppKitView;
      expect(view.viewType, 'attachment_engine/video_view');
      expect(view.creationParams, {'playerId': 'p1'});
      expect(view.creationParamsCodec, isA<StandardMessageCodec>());
    });
  });

  group('share', () {
    test('shareFile forwards path and optional text', () async {
      final received = mockPigeon(
        'ShareHostApi',
        'shareFile',
        ShareHostApi.pigeonChannelCodec,
        null,
      );
      await platform.shareFile('/tmp/a.txt', text: 'look');
      await platform.shareFile('/tmp/b.txt');
      expect(received, [
        ['/tmp/a.txt', 'look'],
        ['/tmp/b.txt', null],
      ]);
    });

    test('shareText forwards the text', () async {
      final received = mockPigeon(
        'ShareHostApi',
        'shareText',
        ShareHostApi.pigeonChannelCodec,
        null,
      );
      await platform.shareText('hello');
      expect(received.single, ['hello']);
    });
  });

  group('openExternally', () {
    test('maps a successful native result', () async {
      final received = mockPigeon(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
        NativeOpenResultMessage(success: true),
      );
      final result = await platform.openExternally(
        '/tmp/a.pdf',
        mimeType: 'application/pdf',
      );
      expect(result.success, isTrue);
      expect(result.message, isNull);
      expect(received.single, ['/tmp/a.pdf', 'application/pdf']);
    });

    test('maps an unsuccessful native result with its message', () async {
      final received = mockPigeon(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
        NativeOpenResultMessage(success: false, message: 'no handler'),
      );
      final result = await platform.openExternally('/tmp/a.xyz');
      expect(result.success, isFalse);
      expect(result.message, 'no handler');
      expect(received.single, ['/tmp/a.xyz', null]);
    });

    test('converts PlatformException into a failed result', () async {
      mockRawReply(
        'OpenHostApi',
        'openExternally',
        OpenHostApi.pigeonChannelCodec,
        ['open-failed', 'cannot open', null],
      );
      final result = await platform.openExternally('/tmp/a.pdf');
      expect(result.success, isFalse);
      expect(result.message, 'cannot open');
    });

    test('converts a missing native handler into a failed result', () async {
      final result = await platform.openExternally('/tmp/a.pdf');
      expect(result.success, isFalse);
      expect(result.message, contains('Unable to establish connection'));
    });
  });

  group('openOfficePreview', () {
    test('invokes the native Office preview Pigeon API', () async {
      final received = mockPigeon(
        'OfficeHostApi',
        'openOfficePreview',
        OfficeHostApi.pigeonChannelCodec,
        null,
      );
      await platform.openOfficePreview('/tmp/f.docx');
      expect(received.single, ['/tmp/f.docx']);
    });

    test('propagates native errors', () {
      mockRawReply(
        'OfficeHostApi',
        'openOfficePreview',
        OfficeHostApi.pigeonChannelCodec,
        ['preview', 'cannot preview', null],
      );
      expect(
        platform.openOfficePreview('/tmp/f.docx'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('paths', () {
    test('getApplicationSupportDirectory returns the native path', () async {
      final received = mockPigeon(
        'PathsHostApi',
        'getApplicationSupportDirectory',
        PathsHostApi.pigeonChannelCodec,
        '/data/support',
      );
      expect(await platform.getApplicationSupportDirectory(), '/data/support');
      expect(received.single, isNull);
    });

    test('getApplicationCacheDirectory returns the native path', () async {
      mockPigeon(
        'PathsHostApi',
        'getApplicationCacheDirectory',
        PathsHostApi.pigeonChannelCodec,
        '/data/cache',
      );
      expect(await platform.getApplicationCacheDirectory(), '/data/cache');
    });

    test('path lookups fail with null-error on a null native path', () {
      mockPigeon(
        'PathsHostApi',
        'getApplicationCacheDirectory',
        PathsHostApi.pigeonChannelCodec,
        null,
      );
      expect(
        platform.getApplicationCacheDirectory(),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'null-error'),
        ),
      );
    });
  });

  group('download', () {
    const headers = {'Authorization': 'Bearer t'};

    test('startDownload forwards args and returns the id', () async {
      final received = mockPigeon(
        'DownloadHostApi',
        'startDownload',
        DownloadHostApi.pigeonChannelCodec,
        'dl-1',
      );
      final id = await platform.startDownload(
        'https://x.test/f',
        headers,
        '/tmp/f',
      );
      expect(id, 'dl-1');
      expect(received.single, ['https://x.test/f', headers, '/tmp/f']);
    });

    test('resumeDownload forwards args and returns the id', () async {
      final received = mockPigeon(
        'DownloadHostApi',
        'resumeDownload',
        DownloadHostApi.pigeonChannelCodec,
        'dl-2',
      );
      final id = await platform.resumeDownload(
        'https://x.test/f',
        const {},
        '/tmp/f',
      );
      expect(id, 'dl-2');
      expect(received.single, [
        'https://x.test/f',
        <Object?, Object?>{},
        '/tmp/f',
      ]);
    });

    test('cancelDownload forwards the id', () async {
      final received = mockPigeon(
        'DownloadHostApi',
        'cancelDownload',
        DownloadHostApi.pigeonChannelCodec,
        null,
      );
      await platform.cancelDownload('dl-1');
      expect(received.single, ['dl-1']);
    });

    test('startDownload propagates native errors', () {
      mockRawReply(
        'DownloadHostApi',
        'startDownload',
        DownloadHostApi.pigeonChannelCodec,
        ['io', 'disk full', null],
      );
      expect(
        platform.startDownload('https://x.test/f', const {}, '/tmp/f'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.message,
            'message',
            'disk full',
          ),
        ),
      );
    });

    test('downloadEvents yields Map events and drops others', () async {
      const name = 'attachment_engine/download_events';
      messenger.setMockMessageHandler(name, (message) async {
        final call = methodCodec.decodeMethodCall(message);
        if (call.method == 'listen') {
          for (final event in <Object?>[
            {'downloadId': 'dl-1', 'type': 'progress', 'received': 5},
            42,
            {'downloadId': 'dl-1', 'type': 'complete', 'path': '/tmp/f'},
          ]) {
            await messenger.handlePlatformMessage(
              name,
              methodCodec.encodeSuccessEnvelope(event),
              (_) {},
            );
          }
        }
        return methodCodec.encodeSuccessEnvelope(null);
      });
      expect(await platform.downloadEvents().take(2).toList(), [
        {'downloadId': 'dl-1', 'type': 'progress', 'received': 5},
        {'downloadId': 'dl-1', 'type': 'complete', 'path': '/tmp/f'},
      ]);
    });
  });
}
