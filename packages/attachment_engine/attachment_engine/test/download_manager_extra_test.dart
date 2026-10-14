// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _Call {
  _Call(this.url, this.hint, this.resume, this.token, this.onProgress);
  final String url;
  final String? hint;
  final bool resume;
  final Object? token;
  final void Function(DownloadProgress)? onProgress;
}

/// A [DownloadClient] whose every call is answered by [handler], recording
/// the arguments and any cancelled tokens.
class _Client implements DownloadClient {
  _Client(this.handler);

  final Future<Uint8List> Function(int index, _Call call) handler;
  final List<_Call> calls = [];
  final List<Object> cancelled = [];
  int _tokens = 0;

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) {
    final call = _Call(url, destinationHint, resume, cancelToken, onProgress);
    calls.add(call);
    return handler(calls.length - 1, call);
  }

  @override
  Object createCancelToken() => 'token-${_tokens++}';

  @override
  void cancel(Object cancelToken) => cancelled.add(cancelToken);
}

Uint8List _bytes(int n) => Uint8List.fromList([n]);

void main() {
  group('DownloadManager basics', () {
    test(
      'returns the bytes and url, passing key as the destination hint',
      () async {
        final client = _Client((i, c) async => _bytes(7));
        final m = DownloadManager(client: client);
        final r = await m.download('key-1', 'https://x/f');
        expect(r.bytes, _bytes(7));
        expect(r.url, 'https://x/f');
        expect(client.calls.single.hint, 'key-1');
        expect(client.calls.single.resume, isFalse);
        expect(client.calls.single.token, 'token-0');
        expect(m.client, same(client));
      },
    );

    test('an empty body is a valid result', () async {
      final m = DownloadManager(client: _Client((i, c) async => Uint8List(0)));
      expect((await m.download('k', 'u')).bytes, isEmpty);
    });

    test('maxRetries positional override wins over config', () async {
      final m = DownloadManager(
        client: _Client((i, c) async => _bytes(1)),
        maxRetries: 9,
        config: const DownloadConfig(maxRetries: 2),
      );
      expect(m.maxRetries, 9);
      expect(
        DownloadManager(
          client: _Client((i, c) async => _bytes(1)),
          config: const DownloadConfig(maxRetries: 2),
        ).maxRetries,
        2,
      );
    });

    test('a non-positive concurrency limit is rejected at construction', () {
      expect(
        () => DownloadManager(
          client: _Client((i, c) async => _bytes(1)),
          config: const DownloadConfig(maxConcurrentDownloads: 0),
        ),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('DownloadResult, DownloadState and DownloadCancelledException', () {
      final r = DownloadResult(bytes: _bytes(1), url: 'u');
      expect(r.url, 'u');
      expect(DownloadState.values.map((s) => s.name), [
        'queued',
        'running',
        'paused',
        'completed',
        'failed',
        'cancelled',
      ]);
      expect(
        const DownloadCancelledException().toString(),
        contains('cancelled'),
      );
    });
  });

  group('DownloadManager retry behaviour', () {
    test('retries up to maxRetries total attempts then rethrows the last '
        'error', () async {
      final client = _Client((i, c) => Future.error(StateError('fail $i')));
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 3,
          retryBackoff: DownloadRetryBackoff.none,
        ),
      );
      await expectLater(
        m.download('k', 'u'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'fail 2'),
        ),
      );
      expect(client.calls, hasLength(3));
    });

    test('maxRetries of 0 and 1 both make exactly one attempt', () async {
      for (final n in [0, 1]) {
        final client = _Client((i, c) => Future.error(StateError('x')));
        final m = DownloadManager(
          client: client,
          config: DownloadConfig(
            maxRetries: n,
            retryBackoff: DownloadRetryBackoff.none,
          ),
        );
        await expectLater(m.download('k', 'u'), throwsA(isA<StateError>()));
        expect(client.calls, hasLength(1), reason: 'maxRetries=$n');
      }
    });

    test('succeeds on a later attempt and marks retries as resume', () async {
      final client = _Client((i, c) async {
        if (i < 2) throw StateError('transient');
        return _bytes(i);
      });
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(retryBackoff: DownloadRetryBackoff.none),
      );
      final r = await m.download('k', 'u');
      expect(r.bytes, _bytes(2));
      expect(client.calls.map((c) => c.resume), [false, true, true]);
    });

    test('resume is never requested when resumeEnabled is false', () async {
      final client = _Client((i, c) async {
        if (i < 1) throw StateError('transient');
        return _bytes(1);
      });
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          resumeEnabled: false,
          retryBackoff: DownloadRetryBackoff.none,
        ),
      );
      await m.download('k', 'u');
      expect(client.calls.map((c) => c.resume), [false, false]);
    });

    test('a cancellation is not retried', () async {
      final client = _Client(
        (i, c) => Future.error(const DownloadCancelledException()),
      );
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(retryBackoff: DownloadRetryBackoff.none),
      );
      await expectLater(
        m.download('k', 'u'),
        throwsA(isA<DownloadCancelledException>()),
      );
      expect(client.calls, hasLength(1));
    });

    testWidgets('exponential backoff doubles the delay between attempts', (
      tester,
    ) async {
      final client = _Client((i, c) => Future.error(StateError('x')));
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 3,
          retryBackoff: DownloadRetryBackoff.exponential,
          retryBaseDelay: Duration(milliseconds: 100),
        ),
      );
      final done = expectLater(
        m.download('k', 'u'),
        throwsA(isA<StateError>()),
      );
      await tester.pump();
      expect(client.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 99));
      expect(client.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(client.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 199));
      expect(client.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(client.calls, hasLength(3));
      await tester.pump(const Duration(seconds: 10));
      await done;
      expect(client.calls, hasLength(3));
    });

    testWidgets('linear backoff grows by the base delay each attempt', (
      tester,
    ) async {
      final client = _Client((i, c) => Future.error(StateError('x')));
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 3,
          retryBackoff: DownloadRetryBackoff.linear,
          retryBaseDelay: Duration(milliseconds: 100),
        ),
      );
      final done = expectLater(
        m.download('k', 'u'),
        throwsA(isA<StateError>()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 199));
      expect(client.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(client.calls, hasLength(3));
      await done;
    });

    testWidgets('a zero base delay retries immediately even with backoff', (
      tester,
    ) async {
      final client = _Client((i, c) => Future.error(StateError('x')));
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 2,
          retryBaseDelay: Duration.zero,
        ),
      );
      final done = expectLater(
        m.download('k', 'u'),
        throwsA(isA<StateError>()),
      );
      await tester.pump();
      expect(client.calls, hasLength(2));
      await done;
    });

    testWidgets('a stalled client times out after connect + receive timeouts', (
      tester,
    ) async {
      final client = _Client((i, c) => Completer<Uint8List>().future);
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 1,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 2),
        ),
      );
      final done = expectLater(
        m.download('k', 'u'),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2, milliseconds: 999));
      expect(client.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await done;
    });

    testWidgets('a timeout is retried like any other failure', (tester) async {
      final client = _Client((i, c) {
        if (i == 0) return Completer<Uint8List>().future;
        return Future.value(_bytes(5));
      });
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 2,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
          retryBackoff: DownloadRetryBackoff.none,
        ),
      );
      final result = m.download('k', 'u');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect((await result).bytes, _bytes(5));
      expect(client.calls, hasLength(2));
    });
  });

  group('DownloadManager concurrency', () {
    test('never runs more than maxConcurrentDownloads and starts queued '
        'downloads in FIFO order as slots free up', () async {
      final gates = <Completer<Uint8List>>[];
      final client = _Client((i, c) {
        final gate = Completer<Uint8List>();
        gates.add(gate);
        return gate.future;
      });
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(maxConcurrentDownloads: 2),
      );
      final f = [for (var i = 0; i < 4; i++) m.download('k$i', 'u$i')];
      await pumpEventQueue();
      expect(client.calls.map((c) => c.url), ['u0', 'u1']);

      gates[0].complete(_bytes(0));
      await pumpEventQueue();
      expect(client.calls.map((c) => c.url), ['u0', 'u1', 'u2']);

      gates[1].complete(_bytes(1));
      await pumpEventQueue();
      expect(client.calls.map((c) => c.url), ['u0', 'u1', 'u2', 'u3']);

      gates[2].complete(_bytes(2));
      gates[3].complete(_bytes(3));
      final results = await Future.wait(f);
      expect(results.map((r) => r.bytes.first), [0, 1, 2, 3]);
    });

    test('a failed download releases its slot for the next one', () async {
      final client = _Client((i, c) async {
        if (i == 0) throw StateError('boom');
        return _bytes(i);
      });
      final m = DownloadManager(
        client: client,
        config: const DownloadConfig(maxConcurrentDownloads: 1, maxRetries: 1),
      );
      final first = m.download('a', 'u0');
      final second = m.download('b', 'u1');
      await expectLater(first, throwsA(isA<StateError>()));
      expect((await second).bytes, _bytes(1));
    });

    test(
      'cancelling a queued download rejects it and it never starts',
      () async {
        final gate = Completer<Uint8List>();
        final client = _Client(
          (i, c) => i == 0 ? gate.future : Future.value(_bytes(i)),
        );
        final m = DownloadManager(
          client: client,
          config: const DownloadConfig(maxConcurrentDownloads: 1),
        );
        final running = m.download('a', 'u0');
        final queued = m.download('b', 'u1');
        final queuedExpectation = expectLater(
          queued,
          throwsA(isA<DownloadCancelledException>()),
        );
        await pumpEventQueue();
        m.cancel('b');
        await queuedExpectation;
        gate.complete(_bytes(0));
        await running;
        expect(client.calls.map((c) => c.url), ['u0']);
      },
    );

    test(
      'cancelling a running download forwards its token to the client',
      () async {
        final gate = Completer<Uint8List>();
        final client = _Client((i, c) => gate.future);
        final m = DownloadManager(client: client);
        final f = m.download('k', 'u');
        final expectation = expectLater(
          f,
          throwsA(isA<DownloadCancelledException>()),
        );
        await pumpEventQueue();
        m.cancel('k');
        expect(client.cancelled, ['token-0']);
        gate.completeError(const DownloadCancelledException());
        await expectation;
      },
    );

    test('cancelling an unknown key is a no-op', () {
      final client = _Client((i, c) async => _bytes(1));
      DownloadManager(client: client).cancel('nope');
      expect(client.cancelled, isEmpty);
    });

    test('cancelling twice only forwards once', () async {
      final gate = Completer<Uint8List>();
      final client = _Client((i, c) => gate.future);
      final m = DownloadManager(client: client);
      final f = m.download('k', 'u');
      final expectation = expectLater(f, throwsA(anything));
      await pumpEventQueue();
      m.cancel('k');
      m.cancel('k');
      expect(client.cancelled, hasLength(1));
      gate.completeError(StateError('x'));
      await expectation;
    });
  });

  group('DownloadManager progress', () {
    test('forwards client progress to the key stream only', () async {
      final gate = Completer<Uint8List>();
      late void Function(DownloadProgress) emit;
      final client = _Client((i, c) {
        emit = c.onProgress!;
        return gate.future;
      });
      final m = DownloadManager(client: client);
      final a = <DownloadProgress>[];
      final other = <DownloadProgress>[];
      final subA = m.progressStream('a').listen(a.add);
      final subOther = m.progressStream('b').listen(other.add);
      final f = m.download('a', 'u');
      await pumpEventQueue();
      emit(const DownloadProgress(received: 1, total: 4));
      emit(const DownloadProgress(received: 4, total: 4));
      await pumpEventQueue();
      expect(a.map((p) => p.fraction), [0.25, 1.0]);
      expect(other, isEmpty);
      gate.complete(_bytes(1));
      await f;
      await subA.cancel();
      await subOther.cancel();
    });

    test('the key stream is closed when the download finishes and a later '
        'subscriber gets a fresh stream', () async {
      final m = DownloadManager(client: _Client((i, c) async => _bytes(1)));
      var done = false;
      m.progressStream('k').listen((_) {}, onDone: () => done = true);
      await m.download('k', 'u');
      await pumpEventQueue();
      expect(done, isTrue);
      final fresh = m.progressStream('k');
      var freshDone = false;
      fresh.listen((_) {}, onDone: () => freshDone = true);
      await pumpEventQueue();
      expect(freshDone, isFalse);
      m.dispose();
    });

    test('progress emitted with no listener and a stream that was never '
        'requested is harmless', () async {
      final client = _Client((i, c) async {
        c.onProgress!(const DownloadProgress(received: 1, total: 2));
        return _bytes(1);
      });
      await DownloadManager(client: client).download('k', 'u');
    });

    test(
      'dispose closes every open progress stream and is idempotent',
      () async {
        final m = DownloadManager(client: _Client((i, c) async => _bytes(1)));
        var closed = 0;
        m.progressStream('a').listen((_) {}, onDone: () => closed++);
        m.progressStream('b').listen((_) {}, onDone: () => closed++);
        m.dispose();
        m.dispose();
        await pumpEventQueue();
        expect(closed, 2);
      },
    );
  });
}
