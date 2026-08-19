import 'package:ansicolor/ansicolor.dart';

/// Draws boxed, bordered UI panels (headers, rows, dividers, menus) to stdout.
class BoxPainter {
  /// Pen used for titles and highlighted headings.
  final AnsiPen titlePen = AnsiPen()..cyan(bold: true);

  /// Pen used for box borders.
  final AnsiPen borderPen = AnsiPen()..white();

  /// Pen used for regular row text.
  final AnsiPen textPen = AnsiPen()..white();

  int _visibleLength(String s) {
    return s.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '').length;
  }

  /// Draws a top-bordered header box containing [title].
  void drawHeader(String title, {int width = 50}) {
    final String horizontalLine = '═' * (width - 2);
    // Structured box-drawing output, not a log message.
    // ignore: avoid_print
    print(borderPen('╔$horizontalLine╗'));

    final int padding = (width - _visibleLength(title) - 2) ~/ 2;
    final String leftPadding = ' ' * padding;
    final String rightPadding =
        ' ' * (width - _visibleLength(title) - padding - 2);

    // ignore: avoid_print
    print(
      '${borderPen('║')}$leftPadding${titlePen(title)}$rightPadding${borderPen('║')}',
    );
    // ignore: avoid_print
    print(borderPen('╠$horizontalLine╣'));
  }

  /// Draws a single labeled row (`key: value`) inside the box.
  void drawRow(String key, String value, {int width = 50}) {
    const labelWidth = 15;
    // 2 (borders) + 2 (left space) + 15 (label) + 2 (colon space) + 1 (right space) = 22 fixed characters.
    // So dynamic content is: width - 22
    final int contentWidth = width - 22;

    final String label = key.padRight(labelWidth);

    final int vLen = _visibleLength(value);
    String content;
    if (vLen > contentWidth) {
      // Stripping ANSI if forced to truncate to avoid broken terminals
      final String stripped =
          value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
      content = '${stripped.substring(0, contentWidth - 3)}...';
    } else {
      final int padCount = contentWidth - vLen;
      content = value + (' ' * padCount);
    }

    // ignore: avoid_print
    print(
      '${borderPen('║')}  ${textPen(label)}: ${textPen(content)} ${borderPen('║')}',
    );
  }

  /// Draws a divider line with a section [text] label.
  void drawDivider(String text, {int width = 50}) {
    final String horizontalLine = '═' * (width - 2);
    // ignore: avoid_print
    print(borderPen('╠$horizontalLine╣'));

    final item = '  $text';
    final String padding = ' ' * (width - _visibleLength(item) - 2);
    // ignore: avoid_print
    print('${borderPen('║')}${titlePen(item)}$padding${borderPen('║')}');
    // ignore: avoid_print
    print(borderPen('╠$horizontalLine╣'));
  }

  /// Draws a numbered menu item row (`[index] label`).
  void drawMenuItem(String index, String label, {int width = 50}) {
    final item = ' [$index] $label';
    final String padding = ' ' * (width - _visibleLength(item) - 2);
    // ignore: avoid_print
    print('${borderPen('║')}${textPen(item)}$padding${borderPen('║')}');
  }

  /// Draws the bottom border closing the box.
  void drawFooter({int width = 50}) {
    final String horizontalLine = '═' * (width - 2);
    // ignore: avoid_print
    print(borderPen('╚$horizontalLine╝'));
  }
}
