// `dart run white_label_kit:init` — thin wrapper so `init` doesn't need the
// `white_label` subcommand prefix. See white_label.dart's `runCli`.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['init', ...args]);
