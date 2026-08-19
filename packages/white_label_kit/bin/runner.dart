// `dart run white_label_kit:runner`
import 'dart:io';

import 'package:white_label_kit/white_label_kit.dart';

Future<void> main(List<String> args) async {
  final int exitCode = await runInteractiveMenu();
  exit(exitCode);
}
