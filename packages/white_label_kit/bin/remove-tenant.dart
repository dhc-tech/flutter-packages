// `dart run white_label_kit:remove-tenant <id>` — thin wrapper, see init.dart / white_label.dart.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['remove-tenant', ...args]);
