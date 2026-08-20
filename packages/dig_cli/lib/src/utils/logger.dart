// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// file: lib/src/utils/logger.dart

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';

/// The category of a log message, used to select color and output stream.
enum LogType {
  /// Informational message (default).
  info,

  /// A successful outcome.
  success,

  /// A warning that doesn't stop execution.
  warning,

  /// An error, written to stderr.
  error,
}

final AnsiPen _infoPen = AnsiPen()..cyan();
final AnsiPen _successPen = AnsiPen()..green();
final AnsiPen _warningPen = AnsiPen()..yellow();
final AnsiPen _errorPen = AnsiPen()..red();

/// True when stdout is a TTY and the user has not disabled ANSI (NO_COLOR, dumb TERM).
bool get kAnsiStdoutEnabled {
  if (Platform.environment.containsKey('NO_COLOR')) {
    return false;
  }
  if (Platform.environment['TERM'] == 'dumb') {
    return false;
  }
  try {
    return stdout.hasTerminal;
  } catch (_) {
    return false;
  }
}

/// Logs [message] to stdout (or stderr for errors), colorized by [type]
/// when ANSI output is enabled.
void kLog(String message, {LogType type = LogType.info}) {
  void plain() {
    switch (type) {
      case LogType.error:
        stderr.writeln(message);
      case LogType.success:
      case LogType.warning:
      case LogType.info:
        // ignore: avoid_print
        print(message);
    }
  }

  if (!kAnsiStdoutEnabled) {
    plain();
    return;
  }

  switch (type) {
    case LogType.success:
      // ignore: avoid_print
      print(_successPen(message));
    case LogType.warning:
      // ignore: avoid_print
      print(_warningPen(message));
    case LogType.error:
      stderr.writeln(_errorPen(message));
    case LogType.info:
      // ignore: avoid_print
      print(_infoPen(message));
  }
}
