// `dart run white_label_kit:build --tenant <id>` — thin wrapper, see
// init.dart / white_label.dart. (The `white_label build` subcommand form
// still exists too and has host-app-vs-generic routing logic; this
// top-level executable always means the generic build, which is what a
// real external consumer always gets anyway since they never have this
// repo's tool/build_runner.dart.)
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['build', ...args]);
