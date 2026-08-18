import 'package:ansicolor/ansicolor.dart';

class BoxPainter {
  final AnsiPen titlePen = AnsiPen()..cyan(bold: true);
  final AnsiPen borderPen = AnsiPen()..white();
  final AnsiPen textPen = AnsiPen()..white();

  int _visibleLength(String s) {
    return s.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '').length;
  }

  void drawHeader(String title, {int width = 50}) {
    final horizontalLine = '═' * (width - 2);
    print(borderPen('╔$horizontalLine╗'));

    final padding = (width - _visibleLength(title) - 2) ~/ 2;
    final leftPadding = ' ' * padding;
    final rightPadding = ' ' * (width - _visibleLength(title) - padding - 2);

    print(
        '${borderPen('║')}$leftPadding${titlePen(title)}$rightPadding${borderPen('║')}');
    print(borderPen('╠$horizontalLine╣'));
  }

  void drawRow(String key, String value, {int width = 50}) {
    final labelWidth = 15;
    // 2 (borders) + 2 (left space) + 15 (label) + 2 (colon space) + 1 (right space) = 22 fixed characters.
    // So dynamic content is: width - 22
    final contentWidth = width - 22;

    final label = key.padRight(labelWidth);

    final vLen = _visibleLength(value);
    String content;
    if (vLen > contentWidth) {
      // Stripping ANSI if forced to truncate to avoid broken terminals
      final stripped = value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
      content = '${stripped.substring(0, contentWidth - 3)}...';
    } else {
      final padCount = contentWidth - vLen;
      content = value + (' ' * padCount);
    }

    print(
        '${borderPen('║')}  ${textPen(label)}: ${textPen(content)} ${borderPen('║')}');
  }

  void drawDivider(String text, {int width = 50}) {
    final horizontalLine = '═' * (width - 2);
    print(borderPen('╠$horizontalLine╣'));

    final item = '  $text';
    final padding = ' ' * (width - _visibleLength(item) - 2);
    print('${borderPen('║')}${titlePen(item)}$padding${borderPen('║')}');
    print(borderPen('╠$horizontalLine╣'));
  }

  void drawMenuItem(String index, String label, {int width = 50}) {
    final item = ' [$index] $label';
    final padding = ' ' * (width - _visibleLength(item) - 2);
    print('${borderPen('║')}${textPen(item)}$padding${borderPen('║')}');
  }

  void drawFooter({int width = 50}) {
    final horizontalLine = '═' * (width - 2);
    print(borderPen('╚$horizontalLine╝'));
  }
}
