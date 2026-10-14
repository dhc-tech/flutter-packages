// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:attachment_engine_web/attachment_engine_web.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Small JS helpers for things the implementation hides behind private
/// bindings: blob URLs to fetch from, reading/writing OPFS directly, and
/// stubbing `navigator.share` / `window.open`.
const String _helpers = r'''
window.__ae = {
  blobUrl(bytes) { return URL.createObjectURL(new Blob([bytes])); },
  async dir(path, create) {
    let d = await navigator.storage.getDirectory();
    for (const s of path.split('/').filter(Boolean)) {
      d = await d.getDirectoryHandle(s, { create });
    }
    return d;
  },
  async write(path, bytes) {
    const parts = path.split('/').filter(Boolean);
    const name = parts.pop();
    const d = await this.dir(parts.join('/'), true);
    const h = await d.getFileHandle(name, { create: true });
    const w = await h.createWritable();
    await w.write(bytes);
    await w.close();
  },
  async read(path) {
    const parts = path.split('/').filter(Boolean);
    const name = parts.pop();
    const d = await this.dir(parts.join('/'), false);
    const h = await d.getFileHandle(name);
    const f = await h.getFile();
    return new Uint8Array(await f.arrayBuffer());
  },
  async exists(path) {
    try { await this.read(path); return true; } catch (e) { return false; }
  },
  stubShare(mode) {
    this.shared = [];
    navigator.share = (data) => {
      this.shared.push(data);
      return mode === 'reject'
        ? Promise.reject(new Error('share cancelled'))
        : Promise.resolve();
    };
  },
  stubOpen(result) {
    this.opened = [];
    this.origOpen = this.origOpen || window.open;
    window.open = (...args) => {
      this.opened.push(args);
      if (result === 'throw') throw new Error('open exploded');
      return result === 'null' ? null : {};
    };
  },
  restore() {
    if (this.origOpen) window.open = this.origOpen;
    delete navigator.share;
  },
  wav(ms) {
    const rate = 8000, n = Math.floor(rate * ms / 1000);
    const b = new ArrayBuffer(44 + n);
    const v = new DataView(b);
    const s = (o, t) => { for (let i = 0; i < t.length; i++) v.setUint8(o + i, t.charCodeAt(i)); };
    s(0, 'RIFF'); v.setUint32(4, 36 + n, true); s(8, 'WAVE'); s(12, 'fmt ');
    v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
    v.setUint32(24, rate, true); v.setUint32(28, rate, true);
    v.setUint16(32, 1, true); v.setUint16(34, 8, true); s(36, 'data');
    v.setUint32(40, n, true);
    for (let i = 0; i < n; i++) v.setUint8(44 + i, 128);
    return new Uint8Array(b);
  },
};
''';

JSObject get _ae => globalContext['__ae']! as JSObject;

Future<T> _awaitJs<T extends JSAny?>(JSAny? promise) =>
    (promise! as JSPromise<T>).toDart;

String _blobUrl(Uint8List bytes) =>
    (_ae.callMethod('blobUrl'.toJS, bytes.toJS)! as JSString).toDart;

Uint8List _wav(int ms) =>
    (_ae.callMethod('wav'.toJS, ms.toJS)! as JSUint8Array).toDart;

Future<void> _opfsWrite(String path, List<int> bytes) => _awaitJs(
  _ae.callMethod('write'.toJS, path.toJS, Uint8List.fromList(bytes).toJS),
);

Future<Uint8List> _opfsRead(String path) async =>
    (await _awaitJs<JSUint8Array>(_ae.callMethod('read'.toJS, path.toJS)))
        .toDart;

Future<bool> _opfsExists(String path) async =>
    (await _awaitJs<JSBoolean>(_ae.callMethod('exists'.toJS, path.toJS)))
        .toDart;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    globalContext.callMethod('eval'.toJS, _helpers.toJS);
  });

  tearDown(() {
    _ae.callMethod('restore'.toJS);
  });

  late AttachmentEngineWebImpl impl;
  var runCounter = 0;
  late String ns;

  setUp(() {
    impl = AttachmentEngineWebImpl();
    ns = 'run${runCounter++}_${DateTime.now().microsecondsSinceEpoch}';
  });

  group('registration', () {
    test('AttachmentEngineWeb.registerWith sets the platform instance', () {
      AttachmentEnginePlatform.instance = AttachmentEngineWebImpl();
      AttachmentEngineWeb.registerWith();
      expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineWebImpl>());
    });

    test('registerWith accepts a registrar argument and installs a new '
        'instance each time', () {
      AttachmentEngineWeb.registerWith();
      final first = AttachmentEnginePlatform.instance;
      AttachmentEngineWeb.registerWith(Object());
      expect(AttachmentEnginePlatform.instance, isNot(same(first)));
    });

    test('AttachmentEngineWebImpl.registerWith sets the platform instance', () {
      AttachmentEnginePlatform.instance = _Placeholder();
      AttachmentEngineWebImpl.registerWith(null);
      expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineWebImpl>());
    });

    test('AttachmentEngineWeb is a const-constructible stateless class', () {
      const a = AttachmentEngineWeb();
      const b = AttachmentEngineWeb();
      expect(identical(a, b), isTrue);
    });
  });

  group('unsupported features', () {
    test('shareFile throws UnimplementedError for any input', () {
      for (final path in ['x', '', '   ', 'a' * 5000]) {
        expect(
          () => impl.shareFile(path, text: 'hi'),
          throwsA(
            isA<UnimplementedError>().having(
              (e) => e.message,
              'message',
              contains('shareFile() is not supported on web'),
            ),
          ),
        );
      }
      expect(() => impl.shareFile('x'), throwsUnimplementedError);
    });

    test('PDF and webview APIs keep the inherited default behavior', () {
      expect(() => impl.pdfOpen('a.pdf'), throwsUnimplementedError);
      expect(() => impl.pdfClose('a'), throwsUnimplementedError);
    });
  });

  group('shareText', () {
    test('hands the text to navigator.share', () async {
      _ae.callMethod('stubShare'.toJS, 'resolve'.toJS);
      await impl.shareText('hello https://example.com');
      final shared = _ae['shared']! as JSArray;
      expect(shared.length, 1);
      expect(
        ((shared as JSObject).getProperty<JSObject>(0.toJS))['text'],
        'hello https://example.com'.toJS,
      );
    });

    test('forwards empty, whitespace, unicode and very long text', () async {
      _ae.callMethod('stubShare'.toJS, 'resolve'.toJS);
      final texts = ['', '   \n\t', 'é\u{1F600}', 'x' * 100000];
      for (final t in texts) {
        await impl.shareText(t);
      }
      final shared = _ae['shared']! as JSObject;
      for (var i = 0; i < texts.length; i++) {
        final entry = shared.getProperty<JSObject>(i.toJS);
        expect((entry['text']! as JSString).toDart, texts[i]);
      }
    });

    test(
      'propagates a rejected share (e.g. user dismissed the sheet)',
      () async {
        _ae.callMethod('stubShare'.toJS, 'reject'.toJS);
        await expectLater(impl.shareText('x'), throwsA(anything));
      },
    );

    test('fails when the Web Share API is unavailable', () async {
      _ae.callMethod('stubShare'.toJS, 'resolve'.toJS);
      globalContext.callMethod('eval'.toJS, 'navigator.share = undefined'.toJS);
      await expectLater(impl.shareText('x'), throwsA(anything));
    });
  });

  group('openExternally', () {
    test('opens the path in a new tab and reports success', () async {
      _ae.callMethod('stubOpen'.toJS, 'ok'.toJS);
      final result = await impl.openExternally(
        'https://example.com/a.pdf',
        mimeType: 'application/pdf',
      );
      expect(result.success, isTrue);
      expect(result.message, isNull);
      final opened = (_ae['opened']! as JSObject).getProperty<JSObject>(0.toJS);
      expect(
        (opened.getProperty<JSString>(0.toJS)).toDart,
        'https://example.com/a.pdf',
      );
      expect((opened.getProperty<JSString>(1.toJS)).toDart, '_blank');
    });

    test(
      'reports a popup-blocked failure when window.open returns null',
      () async {
        _ae.callMethod('stubOpen'.toJS, 'null'.toJS);
        final result = await impl.openExternally('https://example.com');
        expect(result.success, isFalse);
        expect(result.message, contains('blocked'));
      },
    );

    test('maps exceptions from window.open to a failed result', () async {
      _ae.callMethod('stubOpen'.toJS, 'throw'.toJS);
      final result = await impl.openExternally('https://example.com');
      expect(result.success, isFalse);
      expect(result.message, contains('open exploded'));
    });

    test('passes empty and very long paths through unchanged', () async {
      _ae.callMethod('stubOpen'.toJS, 'ok'.toJS);
      final long = 'https://example.com/${'a' * 10000}';
      await impl.openExternally('');
      await impl.openExternally(long);
      final opened = _ae['opened']! as JSObject;
      expect(
        opened
            .getProperty<JSObject>(0.toJS)
            .getProperty<JSString>(0.toJS)
            .toDart,
        '',
      );
      expect(
        opened
            .getProperty<JSObject>(1.toJS)
            .getProperty<JSString>(0.toJS)
            .toDart,
        long,
      );
    });

    test('openOfficePreview falls back to openExternally', () async {
      _ae.callMethod('stubOpen'.toJS, 'ok'.toJS);
      await impl.openOfficePreview('https://example.com/r.docx');
      final opened = (_ae['opened']! as JSObject).getProperty<JSObject>(0.toJS);
      expect(
        opened.getProperty<JSString>(0.toJS).toDart,
        'https://example.com/r.docx',
      );
    });

    test(
      'openOfficePreview completes even when the popup is blocked',
      () async {
        _ae.callMethod('stubOpen'.toJS, 'null'.toJS);
        await expectLater(impl.openOfficePreview('x'), completes);
      },
    );
  });

  group('paths (OPFS)', () {
    test('return stable logical keys', () async {
      expect(
        await impl.getApplicationSupportDirectory(),
        AttachmentEngineWebImpl.supportDirKey,
      );
      expect(
        await impl.getApplicationCacheDirectory(),
        AttachmentEngineWebImpl.cacheDirKey,
      );
      expect(
        AttachmentEngineWebImpl.supportDirKey,
        '/attachment_engine/support',
      );
      expect(AttachmentEngineWebImpl.cacheDirKey, '/attachment_engine/cache');
    });

    test(
      'create the OPFS directory chain on demand and are idempotent',
      () async {
        final a = await impl.getApplicationSupportDirectory();
        final b = await impl.getApplicationSupportDirectory();
        await impl.getApplicationCacheDirectory();
        expect(a, b);
        // Directory exists: writing a file under it succeeds without creating.
        await _opfsWrite('$a/$ns-probe.txt', [1, 2, 3]);
        expect(await _opfsRead('$a/$ns-probe.txt'), [1, 2, 3]);
      },
    );

    test('concurrent calls from separate instances do not race', () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          AttachmentEngineWebImpl().getApplicationCacheDirectory(),
        for (var i = 0; i < 5; i++)
          AttachmentEngineWebImpl().getApplicationSupportDirectory(),
      ]);
      expect(results.take(5).toSet(), {AttachmentEngineWebImpl.cacheDirKey});
      expect(results.skip(5).toSet(), {AttachmentEngineWebImpl.supportDirKey});
    });
  });

  group('downloads', () {
    final payload = List<int>.generate(20000, (i) => i % 253);

    Future<List<Map<Object?, Object?>>> run(
      Future<String> Function() start, {
      Set<String> until = const {'complete', 'error', 'cancelled'},
    }) async {
      final events = <Map<Object?, Object?>>[];
      final done = Completer<void>();
      final sub = impl.downloadEvents().listen((e) {
        events.add(e);
        if (until.contains(e['type']) && !done.isCompleted) done.complete();
      });
      await start();
      await done.future.timeout(const Duration(seconds: 15));
      await sub.cancel();
      return events;
    }

    String dest(String name) => '/attachment_engine/cache/$ns/$name';

    test(
      'startDownload streams a blob into OPFS and reports progress',
      () async {
        final path = dest('ok.bin');
        final url = _blobUrl(Uint8List.fromList(payload));
        final events = await run(() => impl.startDownload(url, {}, path));

        expect(events.last['type'], 'complete');
        expect(events.last['path'], path);
        final progress = events.where((e) => e['type'] == 'progress').toList();
        expect(progress, isNotEmpty);
        expect(progress.last['received'], payload.length);
        expect(progress.last['total'], payload.length);
        expect(
          progress.map((e) => e['received']! as int),
          orderedEquals(
            progress.map((e) => e['received']! as int).toList()..sort(),
          ),
        );
        expect(await _opfsRead(path), payload);
      },
    );

    test('download ids are unique and carry the web prefix', () async {
      final url = _blobUrl(Uint8List.fromList(payload));
      final a = await impl.startDownload(url, {}, dest('a.bin'));
      final b = await impl.startDownload(url, {}, dest('b.bin'));
      expect(a, isNot(b));
      expect(a, startsWith('attachment_engine_web_download_'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });

    test('a zero-byte body completes without progress', () async {
      final path = dest('empty.bin');
      final events = await run(
        () => impl.startDownload(_blobUrl(Uint8List(0)), {}, path),
      );
      expect(events.where((e) => e['type'] == 'progress'), isEmpty);
      expect(events.last['type'], 'complete');
      expect(await _opfsRead(path), isEmpty);
    });

    test('a fresh download replaces existing file contents', () async {
      final path = dest('replace.bin');
      await _opfsWrite(path, List<int>.filled(50000, 7));
      await run(
        () =>
            impl.startDownload(_blobUrl(Uint8List.fromList(payload)), {}, path),
      );
      expect(await _opfsRead(path), payload);
    });

    test('HTTP errors emit an error event', () async {
      final path = dest('missing.bin');
      final events = await run(
        () =>
            impl.startDownload('/__attachment_engine_missing__.bin', {}, path),
      );
      expect(events.single['type'], 'error');
      expect(events.single['message'], 'HTTP 404');
    });

    test('network failures emit an error event with a message', () async {
      final events = await run(
        () => impl.startDownload(
          'http://127.0.0.1:1/unreachable',
          {},
          dest('net.bin'),
        ),
      );
      expect(events.last['type'], 'error');
      expect((events.last['message']! as String), isNotEmpty);
    });

    test('malformed URLs emit an error event', () async {
      for (final bad in ['http://[::bad', 'ht!tp://x']) {
        final events = await run(
          () => impl.startDownload(bad, {}, dest('bad.bin')),
        );
        expect(events.last['type'], 'error', reason: 'url "$bad"');
      }
    });

    test('an empty destination path emits an error event', () async {
      final url = _blobUrl(Uint8List.fromList(payload));
      for (final bad in ['', '/', '///']) {
        final events = await run(() => impl.startDownload(url, {}, bad));
        expect(events.single['type'], 'error', reason: 'path "$bad"');
        expect(events.single['message'], contains('must not be empty'));
      }
    });

    test('request headers are accepted (including empty maps)', () async {
      final url = _blobUrl(Uint8List.fromList(payload));
      final events = await run(
        () => impl.startDownload(url, {'x-custom': 'value'}, dest('h.bin')),
      );
      expect(events.last['type'], 'complete');
    });

    test('resumeDownload on a missing file downloads from the start', () async {
      final path = dest('resume_fresh.bin');
      final events = await run(
        () => impl.resumeDownload(
          _blobUrl(Uint8List.fromList(payload)),
          {},
          path,
        ),
      );
      expect(events.last['type'], 'complete');
      expect(await _opfsRead(path), payload);
    });

    test(
      'resumeDownload with a partial file ends with the full content',
      () async {
        final path = dest('resume_partial.bin');
        await _opfsWrite(path, payload.sublist(0, 8000));
        final events = await run(
          () => impl.resumeDownload(
            _blobUrl(Uint8List.fromList(payload)),
            {},
            path,
          ),
        );
        expect(events.last['type'], 'complete');
        expect(await _opfsRead(path), payload);
      },
    );

    test('resumeDownload restarts from zero when Range is ignored', () async {
      final path = dest('resume_ignored.bin');
      await _opfsWrite(path, List<int>.filled(3000, 9));
      final events = await run(
        () => impl.resumeDownload(
          _blobUrl(Uint8List.fromList(payload)),
          {},
          path,
        ),
      );
      expect(events.last['type'], 'complete');
      final progress = events.where((e) => e['type'] == 'progress').last;
      expect(progress['received'], payload.length);
    });

    test('cancelDownload aborts the transfer and emits cancelled', () async {
      final path = dest('cancel.bin');
      final events = <Map<Object?, Object?>>[];
      final sub = impl.downloadEvents().listen(events.add);
      final id = await impl.startDownload(
        _blobUrl(Uint8List.fromList(payload)),
        {},
        path,
      );
      await impl.cancelDownload(id);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      expect(events.first['type'], 'cancelled');
      expect(events.first['downloadId'], id);
      expect(events.where((e) => e['type'] == 'cancelled'), isNotEmpty);
      expect(events.where((e) => e['type'] == 'error'), isEmpty);
      expect(events.where((e) => e['type'] == 'complete'), isEmpty);
    });

    test('cancelling twice or with an unknown id is a no-op', () async {
      final events = <Map<Object?, Object?>>[];
      final sub = impl.downloadEvents().listen(events.add);
      await impl.cancelDownload('does-not-exist');
      await impl.cancelDownload('');
      final id = await impl.startDownload(
        _blobUrl(Uint8List.fromList(payload)),
        {},
        dest('twice.bin'),
      );
      await impl.cancelDownload(id);
      final before = events.where((e) => e['downloadId'] == id).length;
      await impl.cancelDownload(id);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(events.where((e) => e['downloadId'] == 'does-not-exist'), isEmpty);
      // The second cancel itself adds no event of its own.
      final cancelledByCall = events
          .where(
            (e) =>
                e['downloadId'] == id &&
                e['type'] == 'cancelled' &&
                !e.containsKey('path'),
          )
          .length;
      expect(cancelledByCall, 1);
      expect(before, greaterThanOrEqualTo(1));
    });

    test('concurrent downloads keep events and files separate', () async {
      final events = <Map<Object?, Object?>>[];
      final sub = impl.downloadEvents().listen(events.add);
      final ids = await Future.wait([
        for (var i = 0; i < 4; i++)
          impl.startDownload(
            _blobUrl(Uint8List.fromList(payload)),
            {},
            dest('c$i.bin'),
          ),
      ]);
      while (events.where((e) => e['type'] == 'complete').length < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await sub.cancel();

      expect(ids.toSet(), hasLength(4));
      for (var i = 0; i < 4; i++) {
        final mine = events.where((e) => e['downloadId'] == ids[i]);
        expect(mine.last['type'], 'complete');
        expect(mine.last['path'], dest('c$i.bin'));
        expect(await _opfsRead(dest('c$i.bin')), payload);
      }
    });

    test('downloadEvents is a broadcast stream', () {
      expect(impl.downloadEvents().isBroadcast, isTrue);
    });

    test('paths with nested directories are created on demand', () async {
      final path = '/attachment_engine/cache/$ns/a/b/c/deep.bin';
      final events = await run(
        () =>
            impl.startDownload(_blobUrl(Uint8List.fromList(payload)), {}, path),
      );
      expect(events.last['type'], 'complete');
      expect(await _opfsExists(path), isTrue);
    });
  });

  for (final kind in ['audio', 'video']) {
    group('$kind playback', () {
      late String id;
      setUp(() => id = '${kind}_$ns');

      Future<void> load({String? filePath, String? url}) => kind == 'audio'
          ? impl.audioLoad(id, filePath: filePath, url: url)
          : impl.videoLoad(id, filePath: filePath, url: url);
      Stream<Map<Object?, Object?>> events() =>
          kind == 'audio' ? impl.audioEvents(id) : impl.videoEvents(id);
      Future<void> dispose() =>
          kind == 'audio' ? impl.audioDispose(id) : impl.videoDispose(id);

      Future<Map<Object?, Object?>> waitFor(
        List<Map<Object?, Object?>> seen,
        bool Function(Map<Object?, Object?>) test,
      ) async {
        for (var i = 0; i < 300; i++) {
          final hit = seen.where(test);
          if (hit.isNotEmpty) return hit.first;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail('expected event not received; saw $seen');
      }

      test('load without any source emits an error state', () async {
        final seen = <Map<Object?, Object?>>[];
        final sub = events().listen(seen.add);
        await load();
        await Future<void>.delayed(Duration.zero);
        expect(seen, [
          {'state': 'error'},
        ]);
        await sub.cancel();
      });

      test(
        'load prefers url over filePath and reports buffering then ready',
        () async {
          final seen = <Map<Object?, Object?>>[];
          final sub = events().listen(seen.add);
          await load(filePath: '/ignored/nope.wav', url: _blobUrl(_wav(1000)));

          expect(seen.first, {'state': 'buffering'});
          final ready = await waitFor(seen, (e) => e['state'] == 'ready');
          expect(ready['positionMs'], 0);
          expect(ready['durationMs'], closeTo(1000, 50));
          if (kind == 'video') {
            expect(ready.containsKey('width'), isTrue);
            expect(ready.containsKey('height'), isTrue);
          } else {
            expect(ready.containsKey('width'), isFalse);
          }
          await sub.cancel();
        },
      );

      test('filePath is used when no url is given', () async {
        final seen = <Map<Object?, Object?>>[];
        final sub = events().listen(seen.add);
        await load(filePath: _blobUrl(_wav(500)));
        await waitFor(seen, (e) => e['state'] == 'ready');
        await sub.cancel();
      });

      test('an unplayable source emits an error state', () async {
        final seen = <Map<Object?, Object?>>[];
        final sub = events().listen(seen.add);
        await load(url: _blobUrl(Uint8List.fromList([1, 2, 3, 4])));
        final error = await waitFor(seen, (e) => e['state'] == 'error');
        expect(error, {'state': 'error'});
        await sub.cancel();
      });

      test('seek moves the playhead and is reported via timeupdate', () async {
        final seen = <Map<Object?, Object?>>[];
        final sub = events().listen(seen.add);
        await load(url: _blobUrl(_wav(2000)));
        await waitFor(seen, (e) => e['state'] == 'ready');
        seen.clear();

        if (kind == 'audio') {
          await impl.audioSeek(id, const Duration(milliseconds: 1500));
        } else {
          await impl.videoSeek(id, const Duration(milliseconds: 1500));
        }
        final update = await waitFor(
          seen,
          (e) =>
              (e['positionMs'] as int?) != null &&
              (e['positionMs'] as int) > 1000,
        );
        expect(update['positionMs'], closeTo(1500, 50));
        await sub.cancel();
      });

      test('control calls complete without throwing', () async {
        await load(url: _blobUrl(_wav(500)));
        if (kind == 'audio') {
          await impl.audioSetSpeed(id, 1.5);
          await impl.audioSetSpeed(id, 1);
          await impl.audioSetVolume(id, 0);
          await impl.audioSetVolume(id, 1);
          await impl.audioPause(id);
          await impl.audioSeek(id, Duration.zero);
        } else {
          await impl.videoSetSpeed(id, 1.5);
          await impl.videoSetSpeed(id, 1);
          await impl.videoSetVolume(id, 0);
          await impl.videoSetVolume(id, 1);
          await impl.videoPause(id);
          await impl.videoSeek(id, Duration.zero);
        }
      });

      test('out-of-range volume is rejected by the browser element', () async {
        await load(url: _blobUrl(_wav(500)));
        await expectLater(
          kind == 'audio'
              ? impl.audioSetVolume(id, 2)
              : impl.videoSetVolume(id, 2),
          throwsA(anything),
        );
        await expectLater(
          kind == 'audio'
              ? impl.audioSetVolume(id, -0.1)
              : impl.videoSetVolume(id, -0.1),
          throwsA(anything),
        );
      });

      test('methods lazily create the element for an unknown player', () async {
        final fresh = '${id}_lazy';
        if (kind == 'audio') {
          await impl.audioPause(fresh);
          await impl.audioSetSpeed(fresh, 2);
          await impl.audioDispose(fresh);
        } else {
          await impl.videoPause(fresh);
          await impl.videoSetSpeed(fresh, 2);
          await impl.videoDispose(fresh);
        }
      });

      test(
        'events(playerId) is a broadcast stream shared per player',
        () async {
          expect(events().isBroadcast, isTrue);
          final a = <Map<Object?, Object?>>[];
          final b = <Map<Object?, Object?>>[];
          final s1 = events().listen(a.add);
          final s2 = events().listen(b.add);
          await load();
          await Future<void>.delayed(Duration.zero);
          expect(a, b);
          expect(a, isNotEmpty);
          await s1.cancel();
          await s2.cancel();
        },
      );

      test('players are isolated from each other', () async {
        final seenA = <Map<Object?, Object?>>[];
        final seenB = <Map<Object?, Object?>>[];
        final other = '${id}_other';
        final sa = events().listen(seenA.add);
        final sb =
            (kind == 'audio'
                    ? impl.audioEvents(other)
                    : impl.videoEvents(other))
                .listen(seenB.add);
        await load();
        await Future<void>.delayed(Duration.zero);
        expect(seenA, isNotEmpty);
        expect(seenB, isEmpty);
        await sa.cancel();
        await sb.cancel();
      });

      test('dispose closes the event stream and is idempotent', () async {
        final done = Completer<void>();
        final sub = events().listen((_) {}, onDone: done.complete);
        await load(url: _blobUrl(_wav(300)));
        await dispose();
        await done.future.timeout(const Duration(seconds: 2));
        await dispose();
        await sub.cancel();
      });

      test('a disposed player can be reused with a fresh element', () async {
        await load(url: _blobUrl(_wav(300)));
        await dispose();
        final seen = <Map<Object?, Object?>>[];
        final sub = events().listen(seen.add);
        await load(url: _blobUrl(_wav(300)));
        await waitFor(seen, (e) => e['state'] == 'ready');
        await sub.cancel();
      });
    });
  }

  group('videoBuildView', () {
    testWidgets('returns an HtmlElementView bound to the player view type', (
      tester,
    ) async {
      final widget = impl.videoBuildView('view_$ns');
      expect(widget, isA<HtmlElementView>());
      expect(
        (widget as HtmlElementView).viewType,
        'attachment_engine_web/video/view_$ns',
      );
    });

    testWidgets('repeated calls for one player reuse the registered view', (
      tester,
    ) async {
      final a = impl.videoBuildView('same_$ns') as HtmlElementView;
      final b = impl.videoBuildView('same_$ns') as HtmlElementView;
      expect(a.viewType, b.viewType);
    });

    testWidgets('different players get different view types', (tester) async {
      final a = impl.videoBuildView('p1_$ns') as HtmlElementView;
      final b = impl.videoBuildView('p2_$ns') as HtmlElementView;
      expect(a.viewType, isNot(b.viewType));
    });
  });
}

class _Placeholder extends AttachmentEnginePlatform {}
