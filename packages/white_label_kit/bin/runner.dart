// `dart run white_label_kit:runner`
import 'package:white_label_kit/white_label_kit.dart';

import 'dart:io';

Future<void> main(List<String> args) async {
  final exitCode = await runInteractiveMenu();
  exit(exitCode);
}
