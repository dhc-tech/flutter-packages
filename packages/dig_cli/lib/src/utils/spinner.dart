// file: lib/src/utils/spinner.dart

import 'dart:async';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';

final AnsiPen _infoPen = AnsiPen()..blue();
final AnsiPen _successPen = AnsiPen()..green();
final AnsiPen _errorPen = AnsiPen()..red();

Future<T> runWithSpinner<T>(String message, Future<T> Function() future) async {
  final spinner = ['|', '/', '-', r'\'];
  int i = 0;

  final timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
    stdout.write('\r${_infoPen(message)} ${spinner[i++ % spinner.length]}');
  });

  try {
    final result = await future();
    timer.cancel();
    stdout.write('\r${_successPen(message)} ✅ Done!   \n');
    return result;
  } catch (e) {
    timer.cancel();
    stdout.write('\r${_errorPen(message)} ❌ Failed!  \n');
    rethrow;
  }
}
