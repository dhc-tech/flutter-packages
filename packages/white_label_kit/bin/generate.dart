// `dart run white_label_kit:generate` — thin wrapper, see init.dart /
// white_label.dart. Primary, recommended way to (re)create
// lib/white_label.g.dart — same shape as flutter_native_splash:create /
// icons_launcher:create, no build_runner involved.
import 'white_label.dart' as cli;

Future<void> main(List<String> args) => cli.runCli(['generate', ...args]);
