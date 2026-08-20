// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// `dart run white_label_kit:validate` — thin wrapper, see init.dart / white_label.dart.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['validate', ...args]);
