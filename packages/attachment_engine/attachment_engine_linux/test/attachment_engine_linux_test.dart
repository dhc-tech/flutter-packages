// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:attachment_engine_linux/attachment_engine_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  late AttachmentEngineLinux impl;

  setUp(() {
    impl = AttachmentEngineLinux();
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
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
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(urlLauncherChannel, null);
  });

  List<MethodCall> mockChannel(
    String name, [
    Object? Function(MethodCall)? on,
  ]) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      calls.add(call);
      return on?.call(call);
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
    );
    return calls;
  }

  group('registration', () {
    test('registerWith sets the platform instance', () {
      AttachmentEngineLinux.registerWith();
      expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineLinux>());
    });

    test('is an AttachmentEngineDesktopImpl', () {
      expect(impl, isA<AttachmentEngineDesktopImpl>());
    });
  });

  group('paths', () {
    test('delegate to path_provider', () async {
      expect(
        await impl.getApplicationSupportDirectory(),
        '/tmp/attachment_engine_test/support',
      );
      expect(
        await impl.getApplicationCacheDirectory(),
        '/tmp/attachment_engine_test/cache',
      );
    });
  });

  group('paths (edge cases)', () {
    test('repeated calls are stable and independent', () async {
      final a = await impl.getApplicationSupportDirectory();
      final b = await impl.getApplicationSupportDirectory();
      final c = await impl.getApplicationCacheDirectory();
      expect(a, b);
      expect(c, isNot(a));
    });

    test('path_provider failures propagate', () async {
      messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
        throw PlatformException(code: 'no_dir', message: 'no directory');
      });
      await expectLater(
        impl.getApplicationSupportDirectory(),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        impl.getApplicationCacheDirectory(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a null path_provider response is an error', () async {
      messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
        return null;
      });
      await expectLater(
        impl.getApplicationSupportDirectory(),
        throwsA(anything),
      );
    });

    test('concurrent lookups resolve independently', () async {
      final results = await Future.wait([
        impl.getApplicationSupportDirectory(),
        impl.getApplicationCacheDirectory(),
        impl.getApplicationSupportDirectory(),
      ]);
      expect(results, [
        '/tmp/attachment_engine_test/support',
        '/tmp/attachment_engine_test/cache',
        '/tmp/attachment_engine_test/support',
      ]);
    });
  });

  group('openExternally', () {
    test('succeeds and passes a file URI to url_launcher', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        calls.add(call);
        return true;
      });

      final result = await impl.openExternally('/tmp/doc.pdf');

      expect(result.success, isTrue);
      expect(result.message, isNull);
      final launch = calls.firstWhere((c) => c.method == 'launch');
      expect(launch.arguments['url'], 'file:///tmp/doc.pdf');
    });

    test('reports a message when no application can open the file', () async {
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        return false;
      });

      final result = await impl.openExternally('/tmp/doc.xyz');

      expect(result.success, isFalse);
      expect(result.message, contains('No application registered'));
    });

    test('maps launcher exceptions to a failed result', () async {
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        throw PlatformException(code: 'boom', message: 'launcher exploded');
      });

      final result = await impl.openExternally('/tmp/doc.pdf');

      expect(result.success, isFalse);
      expect(result.message, contains('launcher exploded'));
    });

    test('encodes spaces and unicode in the file URI', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        calls.add(call);
        return true;
      });

      await impl.openExternally('/tmp/my docs/r\u00e9sum\u00e9 #1.pdf');

      final url = calls
          .firstWhere((c) => c.method == 'launch')
          .arguments['url'];
      expect(url, startsWith('file:///tmp/my%20docs/'));
      expect(url, contains('%23'));
      expect(
        Uri.parse(url as String).toFilePath(),
        contains('r\u00e9sum\u00e9 #1.pdf'),
      );
    });

    test(
      'ignores mimeType and handles an empty path without throwing',
      () async {
        messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
          return true;
        });

        final result = await impl.openExternally('', mimeType: 'text/plain');

        expect(result, isA<NativeOpenResult>());
      },
    );

    test('a null launcher response counts as not launched', () async {
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        return null;
      });

      final result = await impl.openExternally('/tmp/a.pdf');

      expect(result.success, isFalse);
      expect(result.message, isNotNull);
    });

    test('openOfficePreview swallows launcher failures', () async {
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        return false;
      });

      await expectLater(impl.openOfficePreview('/tmp/a.docx'), completes);
    });

    test('openOfficePreview falls back to openExternally', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
        calls.add(call);
        return true;
      });

      await impl.openOfficePreview('/tmp/report.docx');

      final launch = calls.firstWhere((c) => c.method == 'launch');
      expect(launch.arguments['url'], 'file:///tmp/report.docx');
    });
  });

  test('shareFile and shareText stay unimplemented (no Linux share API)', () {
    expect(() => impl.shareFile('x'), throwsUnimplementedError);
    expect(() => impl.shareText('x'), throwsUnimplementedError);
  });

  for (final kind in ['audio', 'video']) {
    group('$kind channel', () {
      late List<MethodCall> calls;

      setUp(() => calls = mockChannel('attachment_engine/$kind'));

      Future<void> load(String id, {String? filePath, String? url}) =>
          kind == 'audio'
          ? impl.audioLoad(id, filePath: filePath, url: url)
          : impl.videoLoad(id, filePath: filePath, url: url);

      test('load sends only the provided source', () async {
        await load('p1', url: 'https://example.com/a');
        await load('p1', filePath: '/tmp/a');
        await load('p1', filePath: '/tmp/a', url: 'https://example.com/a');
        await load('p1');

        expect(calls.map((c) => c.method), everyElement('load'));
        expect(calls[0].arguments, {
          'playerId': 'p1',
          'url': 'https://example.com/a',
        });
        expect(calls[1].arguments, {'playerId': 'p1', 'path': '/tmp/a'});
        expect(calls[2].arguments, {
          'playerId': 'p1',
          'path': '/tmp/a',
          'url': 'https://example.com/a',
        });
        expect(calls[3].arguments, {'playerId': 'p1'});
      });

      test('transport controls forward the playerId', () async {
        if (kind == 'audio') {
          await impl.audioPlay('p');
          await impl.audioPause('p');
          await impl.audioDispose('p');
        } else {
          await impl.videoPlay('p');
          await impl.videoPause('p');
          await impl.videoDispose('p');
        }
        expect(calls.map((c) => c.method), ['play', 'pause', 'dispose']);
        for (final c in calls) {
          expect(c.arguments, {'playerId': 'p'});
        }
      });

      test('seek converts the position to milliseconds', () async {
        const pos = Duration(minutes: 1, seconds: 2, milliseconds: 345);
        kind == 'audio'
            ? await impl.audioSeek('p', pos)
            : await impl.videoSeek('p', pos);
        expect(calls.single.method, 'seek');
        expect(calls.single.arguments, {'playerId': 'p', 'positionMs': 62345});
      });

      test('setSpeed and setVolume pass the numeric value', () async {
        if (kind == 'audio') {
          await impl.audioSetSpeed('p', 1.5);
          await impl.audioSetVolume('p', 0.25);
        } else {
          await impl.videoSetSpeed('p', 1.5);
          await impl.videoSetVolume('p', 0.25);
        }
        expect(calls[0].method, 'setSpeed');
        expect(calls[0].arguments, {'playerId': 'p', 'speed': 1.5});
        expect(calls[1].method, 'setVolume');
        expect(calls[1].arguments, {'playerId': 'p', 'volume': 0.25});
      });

      test(
        'edge-case ids and durations are passed through unchanged',
        () async {
          final longId = 'p' * 10000;
          const ids = ['', ' ', 'id with spaces/\u00fc\u{1F3B5}', 'long'];
          for (final id in ids) {
            final pid = id == 'long' ? longId : id;
            if (kind == 'audio') {
              await impl.audioPlay(pid);
            } else {
              await impl.videoPlay(pid);
            }
            expect(calls.last.arguments, {'playerId': pid});
          }

          if (kind == 'audio') {
            await impl.audioSeek('p', Duration.zero);
            await impl.audioSeek('p', const Duration(microseconds: 999));
            await impl.audioSeek('p', const Duration(days: -1));
            await impl.audioSeek('p', const Duration(days: 365 * 100));
            await impl.audioSetSpeed('p', 0);
            await impl.audioSetSpeed('p', -1);
            await impl.audioSetSpeed('p', double.infinity);
            await impl.audioSetVolume('p', 0);
            await impl.audioSetVolume('p', 2);
          } else {
            await impl.videoSeek('p', Duration.zero);
            await impl.videoSeek('p', const Duration(microseconds: 999));
            await impl.videoSeek('p', const Duration(days: -1));
            await impl.videoSeek('p', const Duration(days: 365 * 100));
            await impl.videoSetSpeed('p', 0);
            await impl.videoSetSpeed('p', -1);
            await impl.videoSetSpeed('p', double.infinity);
            await impl.videoSetVolume('p', 0);
            await impl.videoSetVolume('p', 2);
          }
          final args = calls.skip(ids.length).map((c) => c.arguments).toList();
          expect(args[0]['positionMs'], 0);
          expect(args[1]['positionMs'], 0);
          expect(args[2]['positionMs'], -86400000);
          expect(args[3]['positionMs'], 365 * 100 * 86400000);
          expect(args[4]['speed'], 0.0);
          expect(args[5]['speed'], -1.0);
          expect(args[6]['speed'], double.infinity);
          expect(args[7]['volume'], 0.0);
          expect(args[8]['volume'], 2.0);
        },
      );

      test('rapid repeated calls are all delivered in order', () async {
        final futures = [
          for (var i = 0; i < 20; i++)
            kind == 'audio'
                ? impl.audioSeek('p', Duration(milliseconds: i))
                : impl.videoSeek('p', Duration(milliseconds: i)),
        ];
        await Future.wait(futures);
        expect(calls.map((c) => c.arguments['positionMs']), [
          for (var i = 0; i < 20; i++) i,
        ]);
      });

      test(
        'a missing native handler surfaces MissingPluginException',
        () async {
          messenger.setMockMethodCallHandler(
            MethodChannel('attachment_engine/$kind'),
            null,
          );
          final future = kind == 'audio'
              ? impl.audioPlay('p')
              : impl.videoPlay('p');
          await expectLater(future, throwsA(isA<MissingPluginException>()));
        },
      );

      test('event stream drops null events and keeps empty maps', () async {
        final name = 'attachment_engine/${kind}_events/err';
        messenger.setMockStreamHandler(
          EventChannel(name),
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              sink.success(null);
              sink.success(<Object?, Object?>{});
              sink.endOfStream();
            },
          ),
        );
        addTearDown(
          () => messenger.setMockStreamHandler(EventChannel(name), null),
        );

        final stream = kind == 'audio'
            ? impl.audioEvents('err')
            : impl.videoEvents('err');
        expect(await stream.toList(), [<Object?, Object?>{}]);
      });

      test('events for different players use different channels', () async {
        final seen = <String>[];
        for (final id in ['a', 'b']) {
          messenger.setMockStreamHandler(
            EventChannel('attachment_engine/${kind}_events/$id'),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({'id': id});
                sink.endOfStream();
              },
            ),
          );
          addTearDown(
            () => messenger.setMockStreamHandler(
              EventChannel('attachment_engine/${kind}_events/$id'),
              null,
            ),
          );
        }
        for (final id in ['a', 'b']) {
          final s = kind == 'audio'
              ? impl.audioEvents(id)
              : impl.videoEvents(id);
          seen.add((await s.first)['id']! as String);
        }
        expect(seen, ['a', 'b']);
      });

      test('native errors propagate as PlatformException', () async {
        messenger.setMockMethodCallHandler(
          MethodChannel('attachment_engine/$kind'),
          (call) async => throw PlatformException(code: 'native_fail'),
        );
        final future = kind == 'audio'
            ? impl.audioPlay('p')
            : impl.videoPlay('p');
        await expectLater(
          future,
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'native_fail',
            ),
          ),
        );
      });

      test(
        'events are read from a per-player event channel, maps only',
        () async {
          final name = 'attachment_engine/${kind}_events/player7';
          messenger.setMockStreamHandler(
            EventChannel(name),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({'state': 'playing', 'positionMs': 10});
                sink.success('not a map');
                sink.success(42);
                sink.success({'state': 'completed'});
                sink.endOfStream();
              },
            ),
          );
          addTearDown(
            () => messenger.setMockStreamHandler(EventChannel(name), null),
          );

          final stream = kind == 'audio'
              ? impl.audioEvents('player7')
              : impl.videoEvents('player7');

          expect(await stream.toList(), [
            {'state': 'playing', 'positionMs': 10},
            {'state': 'completed'},
          ]);
        },
      );
    });
  }

  group('videoBuildView', () {
    testWidgets('reports its bounds over setLayout after layout', (
      tester,
    ) async {
      final calls = mockChannel('attachment_engine/video');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10.4, top: 20.6),
              child: SizedBox(
                width: 200.4,
                height: 100.6,
                child: impl.videoBuildView('v1'),
              ),
            ),
          ),
        ),
      );

      final layout = calls.where((c) => c.method == 'setLayout').toList();
      expect(layout, isNotEmpty);
      expect(layout.last.arguments, {
        'playerId': 'v1',
        'left': 10,
        'top': 21,
        'width': 200,
        'height': 101,
      });
    });

    testWidgets('reports zero-sized and re-laid-out bounds', (tester) async {
      final calls = mockChannel('attachment_engine/video');
      Widget app(double w, double h) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            height: h,
            child: impl.videoBuildView('v1'),
          ),
        ),
      );

      await tester.pumpWidget(app(0, 0));
      expect(calls.last.arguments['width'], 0);
      expect(calls.last.arguments['height'], 0);

      await tester.pumpWidget(app(320, 180));
      expect(calls.last.arguments['width'], 320);
      expect(calls.last.arguments['height'], 180);
    });

    testWidgets('expands to fill loose constraints', (tester) async {
      mockChannel('attachment_engine/video');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 360),
              child: impl.videoBuildView('v'),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(LayoutBuilder)), const Size(640, 360));
    });

    testWidgets('does not report layout after being unmounted', (tester) async {
      final calls = mockChannel('attachment_engine/video');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: impl.videoBuildView('v1'),
        ),
      );
      calls.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(calls.where((c) => c.method == 'setLayout'), isEmpty);
    });
  });

  group('downloads', () {
    late HttpServer server;
    late Directory tmp;
    late Map<String, String> lastHeaders;
    late List<int> body;
    late Completer<void> gate;

    setUp(() async {
      // The test binding replaces HttpClient with one that always answers
      // 400; downloads need the real one to reach the loopback server.
      HttpOverrides.global = null;
      impl = AttachmentEngineLinux();
      tmp = await Directory.systemTemp.createTemp('ae_download_test');
      body = List<int>.generate(5000, (i) => i % 251);
      lastHeaders = {};
      gate = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        lastHeaders = {};
        req.headers.forEach((k, v) => lastHeaders[k] = v.join(','));
        final res = req.response;
        switch (req.uri.path) {
          case '/ok':
            res.contentLength = body.length;
            res.add(body);
          case '/chunked':
            res.contentLength = -1;
            res.add(body);
          case '/empty':
            res.contentLength = 0;
          case '/missing':
            res.statusCode = 404;
          case '/range':
            final range = req.headers.value('range');
            if (range != null) {
              final start = int.parse(
                RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!,
              );
              res.statusCode = 206;
              final part = body.sublist(start);
              res.contentLength = part.length;
              res.add(part);
            } else {
              res.contentLength = body.length;
              res.add(body);
            }
          case '/slow':
            res.bufferOutput = false;
            res.add(List<int>.filled(1024, 1));
            await res.flush();
            await gate.future;
            res.add(List<int>.filled(1024, 2));
        }
        await res.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    String url(String path) => 'http://127.0.0.1:${server.port}$path';

    Future<List<Map<Object?, Object?>>> run(
      Future<String> Function() start,
    ) async {
      final events = <Map<Object?, Object?>>[];
      final done = Completer<void>();
      final sub = impl.downloadEvents().listen((e) {
        events.add(e);
        if (const {'complete', 'error', 'cancelled'}.contains(e['type'])) {
          if (!done.isCompleted) done.complete();
        }
      });
      final id = await start();
      await done.future.timeout(const Duration(seconds: 10));
      await sub.cancel();
      expect(events.map((e) => e['downloadId']).toSet(), {id});
      return events;
    }

    test(
      'startDownload writes the file and emits progress then complete',
      () async {
        final dest = '${tmp.path}/out.bin';
        final events = await run(
          () => impl.startDownload(url('/ok'), {'x-test': 'yes'}, dest),
        );

        expect(File(dest).readAsBytesSync(), body);
        expect(events.last['type'], 'complete');
        expect(events.last['path'], dest);
        final progress = events.where((e) => e['type'] == 'progress').toList();
        expect(progress, isNotEmpty);
        expect(progress.last['received'], body.length);
        expect(progress.last['total'], body.length);
        expect(lastHeaders['x-test'], 'yes');
        expect(lastHeaders.containsKey('range'), isFalse);
      },
    );

    test('download ids are unique per call', () async {
      final a = await impl.startDownload(url('/ok'), {}, '${tmp.path}/a');
      final b = await impl.startDownload(url('/ok'), {}, '${tmp.path}/b');
      expect(a, isNot(b));
      expect(a, startsWith('attachment_engine_download_'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });

    test('unknown content length reports total -1', () async {
      final dest = '${tmp.path}/chunked.bin';
      final events = await run(
        () => impl.startDownload(url('/chunked'), {}, dest),
      );
      final progress = events.where((e) => e['type'] == 'progress');
      expect(progress, isNotEmpty);
      expect(progress.every((e) => e['total'] == -1), isTrue);
      expect(File(dest).readAsBytesSync(), body);
    });

    test('HTTP errors emit an error event and write nothing', () async {
      final dest = '${tmp.path}/missing.bin';
      final events = await run(
        () => impl.startDownload(url('/missing'), {}, dest),
      );
      expect(events.single['type'], 'error');
      expect(events.single['message'], 'HTTP 404');
      expect(File(dest).existsSync(), isFalse);
    });

    test('connection failures emit an error event', () async {
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);
      final events = await run(
        () => impl.startDownload(
          'http://127.0.0.1:$port/x',
          {},
          '${tmp.path}/dead.bin',
        ),
      );
      expect(events.single['type'], 'error');
      expect(events.single['message'], isNotEmpty);
    });

    test('resumeDownload sends a Range header and appends on 206', () async {
      final dest = '${tmp.path}/resume.bin';
      File(dest).writeAsBytesSync(body.sublist(0, 2000));

      final events = await run(
        () => impl.resumeDownload(url('/range'), {}, dest),
      );

      expect(lastHeaders['range'], 'bytes=2000-');
      expect(events.last['type'], 'complete');
      expect(File(dest).readAsBytesSync(), body);
      final progress = events.where((e) => e['type'] == 'progress').last;
      expect(progress['received'], body.length);
      expect(progress['total'], body.length);
    });

    test(
      'resumeDownload restarts from zero when the server ignores Range',
      () async {
        final dest = '${tmp.path}/restart.bin';
        File(dest).writeAsBytesSync(List<int>.filled(1000, 9));

        final events = await run(
          () => impl.resumeDownload(url('/ok'), {}, dest),
        );

        expect(lastHeaders['range'], 'bytes=1000-');
        expect(events.last['type'], 'complete');
        expect(File(dest).readAsBytesSync(), body);
      },
    );

    test(
      'resumeDownload with no existing file behaves like a fresh download',
      () async {
        final dest = '${tmp.path}/fresh.bin';
        await run(() => impl.resumeDownload(url('/ok'), {}, dest));
        expect(lastHeaders.containsKey('range'), isFalse);
        expect(File(dest).readAsBytesSync(), body);
      },
    );

    test('resumeDownload with an empty existing file sends no Range', () async {
      final dest = '${tmp.path}/empty.bin';
      File(dest).createSync();
      await run(() => impl.resumeDownload(url('/ok'), {}, dest));
      expect(lastHeaders.containsKey('range'), isFalse);
      expect(File(dest).readAsBytesSync(), body);
    });

    test('cancelDownload stops the transfer and emits cancelled', () async {
      final dest = '${tmp.path}/slow.bin';
      final events = <Map<Object?, Object?>>[];
      final done = Completer<void>();
      final sub = impl.downloadEvents().listen((e) {
        events.add(e);
        if (e['type'] == 'progress' && !done.isCompleted) done.complete();
      });
      final id = await impl.startDownload(url('/slow'), {}, dest);
      await done.future.timeout(const Duration(seconds: 10));
      await impl.cancelDownload(id);
      final cancelled = impl.downloadEvents().firstWhere(
        (e) => e['type'] == 'cancelled',
      );
      gate.complete();
      await cancelled.timeout(const Duration(seconds: 10));
      await sub.cancel();

      expect(events.last['type'], 'cancelled');
      expect(events.where((e) => e['type'] == 'complete'), isEmpty);
      expect(File(dest).lengthSync(), lessThanOrEqualTo(1024));
    });

    test('a malformed URL emits an error event', () async {
      final events = await run(
        () => impl.startDownload('http://[::bad', {}, '${tmp.path}/m.bin'),
      );
      expect(events.single['type'], 'error');
      expect(events.single['message'], contains('FormatException'));
    });

    test('an empty URL emits an error event', () async {
      final events = await run(
        () => impl.startDownload('', {}, '${tmp.path}/e.bin'),
      );
      expect(events.single['type'], 'error');
    });

    test('an unwritable destination emits an error event', () async {
      // Closing the failed sink in the implementation's `finally` rethrows
      // the same I/O error from an un-awaited future; swallow it here so the
      // observable contract (an error event, no complete) can be asserted.
      final events = Completer<List<Map<Object?, Object?>>>();
      runZonedGuarded(() async {
        final result = await run(
          () => impl.startDownload(
            url('/ok'),
            {},
            '${tmp.path}/no/such/dir/out.bin',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        events.complete(result);
      }, (error, stack) {});

      final result = await events.future;
      expect(result.last['type'], 'error');
      expect(result.where((e) => e['type'] == 'complete'), isEmpty);
    });

    test('a zero-byte body completes with no progress', () async {
      final dest = '${tmp.path}/zero.bin';
      final events = await run(
        () => impl.startDownload(url('/empty'), {}, dest),
      );
      expect(events.single['type'], 'complete');
      // The sink is only closed (and the empty file materialised) after the
      // complete event is emitted.
      for (var i = 0; i < 50 && !File(dest).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(File(dest).lengthSync(), 0);
    });

    test('a fresh download truncates an existing file', () async {
      final dest = '${tmp.path}/trunc.bin';
      File(dest).writeAsBytesSync(List<int>.filled(9000, 7));
      await run(() => impl.startDownload(url('/ok'), {}, dest));
      expect(File(dest).readAsBytesSync(), body);
    });

    test('request headers are forwarded, including several at once', () async {
      await run(
        () => impl.startDownload(url('/ok'), {
          'authorization': 'Bearer abc',
          'x-one': '1',
          'x-two': '',
        }, '${tmp.path}/h.bin'),
      );
      expect(lastHeaders['authorization'], 'Bearer abc');
      expect(lastHeaders['x-one'], '1');
      expect(lastHeaders.containsKey('x-two'), isTrue);
    });

    test('concurrent downloads keep their events and files separate', () async {
      final events = <Map<Object?, Object?>>[];
      final sub = impl.downloadEvents().listen(events.add);
      final ids = await Future.wait([
        for (var i = 0; i < 4; i++)
          impl.startDownload(url('/ok'), {}, '${tmp.path}/c$i.bin'),
      ]);
      while (events.where((e) => e['type'] == 'complete').length < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await sub.cancel();

      expect(ids.toSet(), hasLength(4));
      for (var i = 0; i < 4; i++) {
        expect(File('${tmp.path}/c$i.bin').readAsBytesSync(), body);
        final mine = events.where((e) => e['downloadId'] == ids[i]);
        expect(mine.last['type'], 'complete');
        expect(mine.last['path'], '${tmp.path}/c$i.bin');
      }
    });

    test('cancelling an unknown id is a harmless no-op', () async {
      final events = <Map<Object?, Object?>>[];
      final sub = impl.downloadEvents().listen(events.add);
      await impl.cancelDownload('nope');
      await impl.cancelDownload('');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(events, isEmpty);
    });

    test(
      'cancelling after completion does not affect later downloads',
      () async {
        final dest = '${tmp.path}/after.bin';
        final events = await run(
          () => impl.startDownload(url('/ok'), {}, dest),
        );
        final id = events.first['downloadId']! as String;
        await impl.cancelDownload(id);
        final next = await run(
          () => impl.startDownload(url('/ok'), {}, '${tmp.path}/after2.bin'),
        );
        expect(next.last['type'], 'complete');
      },
    );

    test(
      'cancelling immediately after start still stops the transfer',
      () async {
        final dest = '${tmp.path}/early.bin';
        final events = <Map<Object?, Object?>>[];
        final sub = impl.downloadEvents().listen(events.add);
        final id = await impl.startDownload(url('/ok'), {}, dest);
        await impl.cancelDownload(id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await sub.cancel();
        final types = events.map((e) => e['type']).toList();
        expect(types.last, anyOf('cancelled', 'complete'));
        expect(types.where((t) => t == 'error'), isEmpty);
      },
    );

    test('downloadEvents is a broadcast stream', () {
      expect(impl.downloadEvents().isBroadcast, isTrue);
    });
  });
}
