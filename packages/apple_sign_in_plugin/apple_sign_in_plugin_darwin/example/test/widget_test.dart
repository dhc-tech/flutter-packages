// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_darwin_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows the Sign in with Apple button', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.byIcon(Icons.apple), findsWidgets);
  });
}
