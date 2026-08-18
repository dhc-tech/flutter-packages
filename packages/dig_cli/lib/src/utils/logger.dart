// file: lib/src/utils/logger.dart

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';

enum LogType { info, success, warning, error }

final AnsiPen _infoPen = AnsiPen()..cyan();
final AnsiPen _successPen = AnsiPen()..green();
final AnsiPen _warningPen = AnsiPen()..yellow();
final AnsiPen _errorPen = AnsiPen()..red();

/// True when stdout is a TTY and the user has not disabled ANSI (NO_COLOR, dumb TERM).
bool get kAnsiStdoutEnabled {
  if (Platform.environment.containsKey('NO_COLOR')) return false;
  if (Platform.environment['TERM'] == 'dumb') return false;
  try {
    return stdout.hasTerminal;
  } catch (_) {
    return false;
  }
}

void kLog(String message, {LogType type = LogType.info}) {
  void plain() {
    switch (type) {
      case LogType.error:
        stderr.writeln(message);
        break;
      default:
        print(message);
    }
  }

  if (!kAnsiStdoutEnabled) {
    plain();
    return;
  }

  switch (type) {
    case LogType.success:
      print(_successPen(message));
      break;
    case LogType.warning:
      print(_warningPen(message));
      break;
    case LogType.error:
      stderr.writeln(_errorPen(message));
      break;
    default:
      print(_infoPen(message));
  }
}
