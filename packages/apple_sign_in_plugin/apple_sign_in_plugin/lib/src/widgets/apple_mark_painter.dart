// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A [CustomPainter] that renders the vector Apple logo mark with HIG-accurate geometry.
///
/// Can be embedded directly into custom button layouts or branding widgets via [CustomPaint].
class AppleMarkPainter extends CustomPainter {
  /// Creates an [AppleMarkPainter] with the given [color].
  const AppleMarkPainter({required this.color});

  /// The fill color of the Apple mark.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = .fill
      ..isAntiAlias = true;

    // Vector viewBox is 170x170 coordinates.
    const baseDimension = 170.0;
    final double scale = math.min(size.width, size.height) / baseDimension;

    canvas.save();
    canvas.translate(
      (size.width - baseDimension * scale) / 2,
      (size.height - baseDimension * scale) / 2,
    );
    canvas.scale(scale, scale);

    final markPath = Path()
      // Apple silhouette body
      ..moveTo(150.37, 130.25)
      ..relativeCubicTo(-2.45, 5.66, -5.35, 10.87, -8.71, 15.66)
      ..relativeCubicTo(-4.58, 6.53, -8.33, 11.05, -11.22, 13.56)
      ..relativeCubicTo(-4.48, 4.12, -9.28, 6.23, -14.42, 6.35)
      ..relativeCubicTo(-3.69, 0.0, -8.14, -1.05, -13.32, -3.18)
      ..relativeCubicTo(-5.19, -2.12, -9.97, -3.17, -14.34, -3.17)
      ..relativeCubicTo(-4.58, 0.0, -9.49, 1.05, -14.75, 3.17)
      ..relativeCubicTo(-5.26, 2.13, -9.5, 3.24, -12.74, 3.35)
      ..relativeCubicTo(-4.35, 0.13, -9.16, -1.9, -14.42, -6.08)
      ..relativeCubicTo(-3.7, -3.08, -7.7, -7.85, -12.0, -14.32)
      ..relativeCubicTo(-6.55, -9.87, -11.75, -20.91, -15.61, -33.14)
      ..relativeCubicTo(-3.86, -12.23, -5.79, -23.77, -5.79, -34.62)
      ..relativeCubicTo(0.0, -14.4, 3.51, -26.68, 10.53, -36.84)
      ..relativeCubicTo(7.02, -10.16, 16.23, -15.39, 27.63, -15.69)
      ..relativeCubicTo(4.96, 0.0, 10.56, 1.41, 16.8, 4.23)
      ..relativeCubicTo(6.24, 2.82, 10.42, 4.29, 12.54, 4.41)
      ..relativeCubicTo(1.76, 0.0, 6.08, -1.59, 12.96, -4.76)
      ..relativeCubicTo(6.88, -3.17, 12.87, -4.58, 17.97, -4.23)
      ..relativeCubicTo(13.59, 0.97, 24.38, 6.27, 32.37, 15.9)
      ..relativeCubicTo(-11.85, 7.18, -17.65, 17.15, -17.4, 29.91)
      ..relativeCubicTo(0.25, 10.05, 4.12, 18.42, 11.62, 25.11)
      ..relativeCubicTo(7.5, 6.69, 16.49, 10.53, 26.97, 11.52)
      ..relativeCubicTo(-2.18, 6.34, -4.88, 12.98, -8.1, 19.92)
      ..close()
      // Leaf
      ..moveTo(119.22, 31.84)
      ..relativeCubicTo(0.0, -7.72, 2.76, -14.99, 8.28, -21.81)
      ..relativeCubicTo(5.52, -6.82, 12.35, -10.84, 20.49, -12.06)
      ..relativeCubicTo(0.33, 1.09, 0.49, 2.18, 0.49, 3.27)
      ..relativeCubicTo(0.0, 7.61, -2.82, 14.94, -8.46, 22.0)
      ..relativeCubicTo(-5.64, 7.06, -12.63, 11.16, -20.97, 12.3)
      ..relativeCubicTo(-0.43, -1.2, -0.84, -2.43, -1.24, -3.7)
      ..close();

    canvas.drawPath(markPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AppleMarkPainter oldDelegate) => oldDelegate.color != color;
}
