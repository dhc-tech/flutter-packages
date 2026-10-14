// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:material_ui/material_ui.dart';

import 'apple_mark_painter.dart';

/// The visual color style applied to an [AppleSignInButton].
enum AppleButtonStyle {
  /// Black background with white text and logo mark. Recommended on light or white backgrounds.
  black,

  /// White background with black text and logo mark. Recommended on dark backgrounds.
  white,

  /// White background with a 1px solid black outline, black text, and logo mark.
  whiteOutlined,
}

/// The relative placement of the Apple logo mark within an [AppleSignInButton].
enum AppleButtonIconAlignment {
  /// Aligns the logo mark and title horizontally together in the center.
  center,

  /// Pins the logo mark towards the left margin while keeping the title centered.
  left,
}

/// A first-party, Apple HIG-compliant button widget provided by `apple_sign_in_plugin`.
///
/// Features:
/// - Exact HIG visual themes via [AppleButtonStyle].
/// - Flexible layout alignments via [AppleButtonIconAlignment].
/// - Dedicated constructors: [AppleSignInButton.new], [AppleSignInButton.continueWith],
///   [AppleSignInButton.signUp], and [AppleSignInButton.iconOnly].
/// - Built-in vector drawing with [AppleMarkPainter] — zero external icon fonts or assets needed.
/// - Full accessibility semantics and responsive tap feedback.
class AppleSignInButton extends StatelessWidget {
  /// Creates a standard "Sign in with Apple" button.
  const AppleSignInButton({
    super.key,
    required this.onPressed,
    this.text = 'Sign in with Apple',
    this.style = .black,
    this.iconAlignment = .center,
    this.height = 44.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    this.textStyle,
  }) : _isIconOnly = false;

  /// Creates a "Continue with Apple" button.
  const AppleSignInButton.continueWith({
    super.key,
    required this.onPressed,
    this.style = .black,
    this.iconAlignment = .center,
    this.height = 44.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    this.textStyle,
  }) : text = 'Continue with Apple',
       _isIconOnly = false;

  /// Creates a "Sign up with Apple" button.
  const AppleSignInButton.signUp({
    super.key,
    required this.onPressed,
    this.style = .black,
    this.iconAlignment = .center,
    this.height = 44.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    this.textStyle,
  }) : text = 'Sign up with Apple',
       _isIconOnly = false;

  /// Creates a compact, icon-only Apple button.
  const AppleSignInButton.iconOnly({
    super.key,
    required this.onPressed,
    this.style = .black,
    this.height = 44.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
  }) : text = 'Sign in with Apple',
       iconAlignment = .center,
       textStyle = null,
       _isIconOnly = true;

  /// The callback invoked when the button is tapped.
  ///
  /// When `null`, the button renders in a disabled state with reduced opacity.
  final VoidCallback? onPressed;

  /// The button title string displayed beside the logo mark.
  final String text;

  /// The visual color theme.
  final AppleButtonStyle style;

  /// The placement of the logo mark inside the button.
  final AppleButtonIconAlignment iconAlignment;

  /// The vertical height of the button.
  final double height;

  /// Corner radius for the button background.
  final BorderRadius borderRadius;

  /// Optional custom typography styling override.
  final TextStyle? textStyle;

  final bool _isIconOnly;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    final Color backgroundColor;
    final Color foregroundColor;
    final Border? border;

    switch (style) {
      case .black:
        backgroundColor = const Color(0xFF000000);
        foregroundColor = const Color(0xFFFFFFFF);
        border = null;
      case .white:
        backgroundColor = const Color(0xFFFFFFFF);
        foregroundColor = const Color(0xFF000000);
        border = null;
      case .whiteOutlined:
        backgroundColor = const Color(0xFFFFFFFF);
        foregroundColor = const Color(0xFF000000);
        border = Border.all();
    }

    final double effectiveFontSize = height * 0.38;
    final double iconSize = height * 0.45;

    final Widget logo = CustomPaint(
      size: Size.square(iconSize),
      painter: AppleMarkPainter(color: foregroundColor),
    );

    final Widget content;
    if (_isIconOnly) {
      content = Center(child: logo);
    } else {
      final TextStyle effectiveTextStyle = (textStyle ?? const TextStyle()).copyWith(
        color: foregroundColor,
        fontSize: textStyle?.fontSize ?? effectiveFontSize,
        fontWeight: textStyle?.fontWeight ?? .w600,
        letterSpacing: textStyle?.letterSpacing ?? -0.4,
      );

      final Widget label = Text(text, style: effectiveTextStyle, maxLines: 1, overflow: .ellipsis);

      switch (iconAlignment) {
        case .center:
          content = Row(
            mainAxisAlignment: .center,
            mainAxisSize: .min,
            children: [
              logo,
              SizedBox(width: height * 0.2),
              Flexible(child: label),
            ],
          );
        case .left:
          content = Stack(
            alignment: .center,
            children: [
              Align(
                alignment: .centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: height * 0.35),
                  child: logo,
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: height * 0.8),
                  child: label,
                ),
              ),
            ],
          );
      }
    }

    Widget button = Container(
      width: _isIconOnly ? height : null,
      height: height,
      decoration: BoxDecoration(color: backgroundColor, borderRadius: borderRadius, border: border),
      child: Material(
        type: .transparency,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onPressed,
          child: Center(child: content),
        ),
      ),
    );

    if (!isEnabled) {
      button = Opacity(opacity: 0.38, child: button);
    }

    return Semantics(button: true, enabled: isEnabled, label: text, child: button);
  }
}
