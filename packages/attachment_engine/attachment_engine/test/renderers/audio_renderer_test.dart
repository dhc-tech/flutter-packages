// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and lets a test push synthetic native events, standing in
/// for the real iOS/Android platform packages (which this package cannot
/// depend on without a cycle).
class _RecordingPlatform extends AttachmentEnginePlatform {
  _RecordingPlatform({this.failVolumeSetting = false});

  /// When true, [audioSetVolume] rejects — exercises the revert-on-failure
  /// path in [NativeAudioController.setVolume].
  final bool failVolumeSetting;

  final List<String> calls = [];
  final _controllers = <String, StreamController<Map<Object?, Object?>>>{};

  StreamController<Map<Object?, Object?>> _controllerFor(String playerId) =>
      _controllers.putIfAbsent(
        playerId,
        () => StreamController<Map<Object?, Object?>>.broadcast(),
      );

  void emit(String playerId, Map<Object?, Object?> event) =>
      _controllerFor(playerId).add(event);

  @override
  Stream<Map<Object?, Object?>> audioEvents(String playerId) =>
      _controllerFor(playerId).stream;

  @override
  Future<void> audioLoad(String playerId, {String? filePath, String? url}) {
    calls.add('audioLoad:$playerId:${filePath ?? url}');
    return Future.value();
  }

  @override
  Future<void> audioPlay(String playerId) {
    calls.add('audioPlay:$playerId');
    return Future.value();
  }

  @override
  Future<void> audioPause(String playerId) {
    calls.add('audioPause:$playerId');
    return Future.value();
  }

  @override
  Future<void> audioSeek(String playerId, Duration position) {
    calls.add('audioSeek:$playerId:${position.inMilliseconds}');
    return Future.value();
  }

  @override
  Future<void> audioSetVolume(String playerId, double volume) {
    calls.add('audioSetVolume:$playerId:$volume');
    if (failVolumeSetting) {
      return Future.error(StateError('player disposed'));
    }
    return Future.value();
  }

  @override
  Future<void> audioDispose(String playerId) {
    calls.add('audioDispose:$playerId');
    return Future.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Attachment audioAttachment(String id) => Attachment(
    id: id,
    name: 'note.mp3',
    source: AttachmentSource.url('https://example.com/$id.mp3'),
    remoteUrl: 'https://example.com/$id.mp3',
    attachmentType: AttachmentType.audio,
    status: AttachmentStatus.ready,
  );

  /// [NativeAudioController.playerId] is an incrementing counter, not
  /// derived from the attachment — recovered from the first `audioLoad`
  /// call the widget makes so the test can address the right event stream.
  String playerIdFromFirstLoad(_RecordingPlatform platform) {
    final call = platform.calls.firstWhere((c) => c.startsWith('audioLoad:'));
    return call.split(':')[1];
  }

  late _RecordingPlatform platform;

  setUp(() {
    platform = _RecordingPlatform();
    AttachmentEnginePlatform.instance = platform;
  });

  testWidgets('shows position/duration readout and a working volume slider', (
    tester,
  ) async {
    const renderer = AudioAttachmentRenderer();
    final attachment = audioAttachment('audio-controls-test');

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Builder(
            builder: (context) => renderer.build(context, attachment),
          ),
        ),
      ),
    );
    await tester.pump();

    final playerId = playerIdFromFirstLoad(platform);
    platform.emit(playerId, {
      'state': 'playing',
      'positionMs': 5000,
      'durationMs': 65000,
    });
    // Two hops of broadcast-stream delivery (platform -> NativeAudioController
    // -> this StreamBuilder), each an async event dispatch — one pump only
    // flushes the first hop, so a second is needed before the rebuild lands.
    await tester.pump();
    await tester.pump();

    // Duration/position readout — this is what was entirely missing before:
    // only a bare Slider with no numbers next to it.
    expect(find.text('00:05'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);

    // Two sliders now: seek (position) and volume.
    expect(find.byType(Slider), findsNWidgets(2));

    final volumeSlider = tester.widget<Slider>(find.byType(Slider).last);
    (volumeSlider.onChanged!)(0.4);
    await tester.pump();

    expect(
      platform.calls.any((c) => c == 'audioSetVolume:$playerId:0.4'),
      isTrue,
    );
    // Moving the slider updates the shared controller-level value, not
    // per-widget state — the same volume slider reads it back.
    expect(
      tester.widget<Slider>(find.byType(Slider).last).value,
      0.4,
    );
  });

  testWidgets('formats a duration of an hour or more with an hours component', (
    tester,
  ) async {
    const renderer = AudioAttachmentRenderer();
    final attachment = audioAttachment('audio-long-duration-test');

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Builder(
            builder: (context) => renderer.build(context, attachment),
          ),
        ),
      ),
    );
    await tester.pump();

    final playerId = playerIdFromFirstLoad(platform);
    // 1h05m00s — `inMinutes.remainder(60)` alone would render this as
    // "05:00", silently dropping the hour.
    platform.emit(playerId, {
      'state': 'playing',
      'positionMs': 0,
      'durationMs': 3900000,
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('1:05:00'), findsOneWidget);
  });

  testWidgets(
    'renders an error message and Retry button on playback failure',
    (tester) async {
      const renderer = AudioAttachmentRenderer();
      final attachment = audioAttachment('audio-error-test');

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Builder(
              builder: (context) => renderer.build(context, attachment),
            ),
          ),
        ),
      );
      await tester.pump();

      final playerId = playerIdFromFirstLoad(platform);
      platform.emit(playerId, {'state': 'error'});
      await tester.pump();
      await tester.pump();

      expect(find.text('This audio could not be played.'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

      final loadCallsBefore = platform.calls
          .where((c) => c.startsWith('audioLoad:'))
          .length;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      final loadCallsAfter = platform.calls
          .where((c) => c.startsWith('audioLoad:'))
          .length;

      expect(loadCallsAfter, loadCallsBefore + 1);
    },
  );

  testWidgets(
    'reverts the volume slider if the platform volume call fails, without '
    'an unhandled error',
    (tester) async {
      platform = _RecordingPlatform(failVolumeSetting: true);
      AttachmentEnginePlatform.instance = platform;

      const renderer = AudioAttachmentRenderer();
      final attachment = audioAttachment('audio-volume-failure-test');

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Builder(
              builder: (context) => renderer.build(context, attachment),
            ),
          ),
        ),
      );
      await tester.pump();

      final volumeSlider = tester.widget<Slider>(find.byType(Slider).last);
      expect(volumeSlider.value, 1);

      (volumeSlider.onChanged!)(0.4);
      // One pump for the optimistic update, one more for the revert once
      // the rejected Future completes.
      await tester.pump();
      await tester.pump();

      // Reverted back to the pre-drag value — no error escapes to fail the
      // test (flutter_test fails the test on any unhandled exception, so
      // simply reaching this assertion is itself part of the coverage).
      expect(tester.widget<Slider>(find.byType(Slider).last).value, 1);
    },
  );
}
