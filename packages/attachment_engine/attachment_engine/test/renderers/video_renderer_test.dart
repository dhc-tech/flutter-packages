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
  Stream<Map<Object?, Object?>> videoEvents(String playerId) =>
      _controllerFor(playerId).stream;

  @override
  Future<void> videoLoad(String playerId, {String? filePath, String? url}) {
    calls.add('videoLoad:$playerId:${filePath ?? url}');
    return Future.value();
  }

  @override
  Future<void> videoPlay(String playerId) {
    calls.add('videoPlay:$playerId');
    return Future.value();
  }

  @override
  Future<void> videoPause(String playerId) {
    calls.add('videoPause:$playerId');
    return Future.value();
  }

  @override
  Widget videoBuildView(String playerId) => const SizedBox.shrink();

  @override
  Future<void> videoDispose(String playerId) {
    calls.add('videoDispose:$playerId');
    return Future.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Attachment videoAttachment(String id) => Attachment(
    id: id,
    name: 'clip.mp4',
    source: AttachmentSource.url('https://example.com/$id.mp4'),
    remoteUrl: 'https://example.com/$id.mp4',
    attachmentType: AttachmentType.video,
    status: AttachmentStatus.ready,
  );

  /// The [playerId] a controller acquires is an incrementing counter, not
  /// derived from the attachment — recovered from the first `videoLoad`
  /// call the widget makes so the test can address the right event stream.
  String playerIdFromFirstLoad(_RecordingPlatform platform) {
    final call = platform.calls.firstWhere((c) => c.startsWith('videoLoad:'));
    return call.split(':')[1];
  }

  late _RecordingPlatform platform;

  setUp(() {
    platform = _RecordingPlatform();
    AttachmentEnginePlatform.instance = platform;
  });

  testWidgets('renders an error message and Retry button on failure', (
    tester,
  ) async {
    const renderer = VideoAttachmentRenderer();
    final attachment = videoAttachment('video-error-test');

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

    // Still idle/buffering — spinner, no error UI yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('This video could not be played.'), findsNothing);

    final playerId = playerIdFromFirstLoad(platform);
    platform.emit(playerId, {'state': 'error'});
    await tester.pump();

    expect(find.text('This video could not be played.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final loadCallsBefore = platform.calls
        .where((c) => c.startsWith('videoLoad:'))
        .length;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    final loadCallsAfter = platform.calls
        .where((c) => c.startsWith('videoLoad:'))
        .length;

    expect(loadCallsAfter, loadCallsBefore + 1);
  });
}
