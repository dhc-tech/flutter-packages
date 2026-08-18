import 'package:ansicolor/ansicolor.dart';
import 'package:dig_cli/src/ui/box_painter.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    ansiColorDisabled = true;
  });

  group('BoxPainter Tests', () {
    test('BoxPainter initializes correctly without error', () {
      final painter = BoxPainter();
      expect(painter, isNotNull);
      expect(painter.titlePen, isNotNull);
      expect(painter.borderPen, isNotNull);
      expect(painter.textPen, isNotNull);
    });

    test('BoxPainter draw methods execute without throwing', () {
      final painter = BoxPainter();
      expect(
          () => painter.drawHeader('DHC Tech CLI', width: 60), returnsNormally);
      expect(() => painter.drawRow('Version', '1.8.0', width: 60),
          returnsNormally);
      expect(
          () => painter.drawRow('Long Key With Value',
              'A very long value string that exceeds standard width to test truncation',
              width: 40),
          returnsNormally);
      expect(() => painter.drawDivider('Commands', width: 60), returnsNormally);
      expect(() => painter.drawMenuItem('1', 'Build Release', width: 60),
          returnsNormally);
      expect(() => painter.drawFooter(width: 60), returnsNormally);
    });
  });
}
