// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// `dart run white_label_kit:init` — thin wrapper so `init` doesn't need the
// `white_label` subcommand prefix. See white_label.dart's `runCli`.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['init', ...args]);
