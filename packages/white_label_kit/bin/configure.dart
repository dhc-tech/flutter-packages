// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// `dart run white_label_kit:configure` — thin wrapper, see white_label.dart.
// The zero-touch setup command: patches Android build.gradle.kts and iOS
// Xcode project for every declared tenant in white_label.yaml, then
// re-generates lib/white_label.g.dart.  Run once after `init` / `add-tenant`
// and your Flutter project is immediately ready for `flutter build --flavor`.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['configure', ...args]);
