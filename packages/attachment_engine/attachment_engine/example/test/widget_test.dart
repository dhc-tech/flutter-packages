// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Basic smoke test for the attachment_engine example app: the app should
// launch to the attachment list page without throwing.

import 'package:attachment_engine_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App launches and shows the attachment list page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AttachmentEngineExampleApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
