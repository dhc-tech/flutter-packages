// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AppleSignInButton Widget Tests', () {
    testWidgets('renders default button and triggers onPressed', (WidgetTester tester) async {
      var pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: AppleSignInButton(onPressed: () => pressed = true)),
          ),
        ),
      );

      expect(find.text('Sign in with Apple'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.tap(find.byType(AppleSignInButton));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('renders continueWith named constructor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: AppleSignInButton.continueWith(onPressed: () {})),
          ),
        ),
      );

      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsNothing);
    });

    testWidgets('renders signUp named constructor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: AppleSignInButton.signUp(onPressed: () {})),
          ),
        ),
      );

      expect(find.text('Sign up with Apple'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsNothing);
    });

    testWidgets('renders iconOnly named constructor without text label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: AppleSignInButton.iconOnly(onPressed: () {})),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      // Label text should not be rendered in icon-only mode
      expect(find.text('Sign in with Apple'), findsNothing);
    });

    testWidgets('handles disabled state when onPressed is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: AppleSignInButton(onPressed: null))),
        ),
      );

      final Finder opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);

      final Opacity opacityWidget = tester.widget(opacityFinder);
      expect(opacityWidget.opacity, 0.38);

      final Semantics semantics = tester.widget(
        find.descendant(of: find.byType(AppleSignInButton), matching: find.byType(Semantics)).first,
      );
      expect(semantics.properties.enabled, isFalse);
    });

    testWidgets('renders white and whiteOutlined styles correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AppleSignInButton(onPressed: () {}, style: .white),
                AppleSignInButton(onPressed: () {}, style: .whiteOutlined),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AppleSignInButton), findsNWidgets(2));
    });

    testWidgets('renders left and center icon alignments correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AppleSignInButton(onPressed: () {}),
                AppleSignInButton(onPressed: () {}, iconAlignment: .left),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AppleSignInButton), findsNWidgets(2));
    });
  });

  group('AppleMarkPainter Tests', () {
    test('shouldRepaint returns true on different color and false on same color', () {
      const painter1 = AppleMarkPainter(color: Color(0xFF000000));
      const painter2 = AppleMarkPainter(color: Color(0xFFFFFFFF));
      const painter3 = AppleMarkPainter(color: Color(0xFF000000));

      expect(painter1.shouldRepaint(painter2), isTrue);
      expect(painter1.shouldRepaint(painter3), isFalse);
    });
  });
}
