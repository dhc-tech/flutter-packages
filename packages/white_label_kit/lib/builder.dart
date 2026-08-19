/// OPTIONAL, advanced alternative to `dart run white_label_kit:generate`
/// (see `bin/generate.dart` — that's the primary, recommended path, the
/// same way `flutter_native_splash:create`/`icons_launcher:create` work:
/// one direct command, no `build_runner` involved). If your project already
/// runs `dart run build_runner build` for `freezed`/`json_serializable`/
/// `injectable_generator`, this lets that same command also regenerate
/// `lib/white_label.g.dart` — but it requires a `build.yaml` `sources:`
/// override (`white_label.yaml` sits at the project root, outside
/// `build_runner`'s default `lib/**` scan) that `generate`/`init` do not.
/// Both paths call the exact same generation logic
/// (`lib/src/generation/dart_config_generator.dart`) — pick whichever fits
/// your project, they produce identical output.
///
/// Registered via `build.yaml`'s `white_label_generator` entry
/// (`auto_apply: dependents` — any app that depends on this package and has
/// `build_runner` as a dev_dependency gets this applied automatically, the
/// same way adding `freezed_annotation` auto-applies the `freezed` builder).
library;

import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';

import 'src/config/white_label_config.dart';
import 'src/generation/dart_config_generator.dart';

/// Builder factory registered via `build.yaml`'s `white_label_generator`.
Builder whiteLabelBuilder(BuilderOptions options) => WhiteLabelBuilder();

/// See this library's dartdoc — a thin `build_runner` wrapper around
/// [generateWhiteLabelSource]/[resolveGeneratorTenantId], for projects that
/// prefer triggering generation via `build_runner` instead of the direct
/// `generate` CLI command.
class WhiteLabelBuilder implements Builder {
  /// Creates the builder, optionally overriding the environment used for
  /// tenant-selection.
  WhiteLabelBuilder({this.environmentOverride});

  /// Overrides [Platform.environment] for tenant-selection purposes —
  /// `null` (the real-world default) means use the real environment.
  /// Exists so `test/builder_test.dart` can exercise `TENANT_ID` selection
  /// deterministically without forking a real subprocess per test case.
  final Map<String, String>? environmentOverride;

  @override
  Map<String, List<String>> get buildExtensions => {
    'white_label.yaml': ['lib/white_label.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final String yamlText = await buildStep.readAsString(buildStep.inputId);

    final WhiteLabelConfig config;
    try {
      config = WhiteLabelConfig.parse(yamlText);
    } on WhiteLabelConfigException catch (e) {
      log.severe('white_label.yaml is invalid:\n$e');
      rethrow;
    }

    final String selectedId = resolveGeneratorTenantId(config, environment: environmentOverride);

    final outputId = AssetId(buildStep.inputId.package, 'lib/white_label.g.dart');
    await buildStep.writeAsString(outputId, generateWhiteLabelSource(config, selectedId));
  }
}
