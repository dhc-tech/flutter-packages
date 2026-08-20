// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// `dart run white_label_kit:menu` or `dart run white_label_kit:runner`
// Launches the interactive multi-tenant runner and builder.
import 'dart:io';

import 'package:white_label_kit/white_label_kit.dart';

Future<void> main(List<String> args) async {
  final int exitCode = await runInteractiveMenu();
  exit(exitCode);
}
