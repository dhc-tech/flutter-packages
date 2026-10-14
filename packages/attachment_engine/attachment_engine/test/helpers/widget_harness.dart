// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:attachment_engine/src/renderers/text_renderer.dart'
    show CircularProgressIndicatorPlaceholder;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Wraps [child] in a [MaterialApp] with an explicit text direction, text
/// scale and brightness so one widget can be exercised in LTR/RTL,
/// light/dark and accessibility-scaled variants.
Widget harness(
  Widget child, {
  TextDirection textDirection = TextDirection.ltr,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    builder: (context, app) => Directionality(
      textDirection: textDirection,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
    ),
    home: Scaffold(body: child),
  );
}

/// Sets the logical viewport size for [tester] (device pixel ratio 1) and
/// restores it when the test ends.
void setScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps real-async frames until [finder] matches, for widgets that wait on
/// genuine file I/O (which fake-async `pump` alone cannot complete). The
/// loop is condition-driven and bounded, not a fixed wall-clock wait.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 1000,
}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// A valid 1x1 transparent PNG.
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Pumps real-async frames until [condition] holds (bounded; fails with
/// [reason] otherwise). For flows that complete via genuine file I/O.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String reason = 'condition',
  int maxTries = 1000,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
  }
  if (!condition()) fail('Timed out waiting for $reason');
}

/// Waits, bounded and without a fixed sleep, until every loading placeholder of
/// a file-reading renderer has gone. File reads complete on real async time, so
/// a fixed delay is flaky when the machine is busy.
Future<void> settleLoading(WidgetTester tester, {int maxTries = 2000}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicatorPlaceholder).evaluate().isEmpty) {
      return;
    }
  }
  fail('Timed out waiting for the renderer to finish loading');
}
