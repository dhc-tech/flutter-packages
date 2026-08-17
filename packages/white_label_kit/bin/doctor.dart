// `dart run white_label_kit:doctor` — thin wrapper, see init.dart / white_label.dart.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['doctor', ...args]);
