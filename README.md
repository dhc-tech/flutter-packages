# Flutter Packages

[![CI Validate](https://github.com/dhc-tech/flutter-packages/actions/workflows/validate.yml/badge.svg)](https://github.com/dhc-tech/flutter-packages/actions/workflows/validate.yml)
[![Flutter: >=3.47.7](https://img.shields.io/badge/Flutter-%3E%3D3.47.7-blue.svg)](https://flutter.dev)
[![Dart: ^3.13.5](https://img.shields.io/badge/Dart-%5E3.13.5-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

This repository hosts production-ready Flutter and Dart packages developed and maintained by **Digvijaysinh Chauhan** and **DHC Tech**.
Browse the [`packages`](./packages) directory to explore each package and its examples.

All published packages are available on [pub.dev](https://pub.dev/).

## Packages

| Package | Pub | Points | Usage | Issues |
|---|---|---|---|---|
| [apple_sign_in_plugin](./packages/apple_sign_in_plugin/apple_sign_in_plugin/) | [![pub package](https://img.shields.io/pub/v/apple_sign_in_plugin.svg)](https://pub.dev/packages/apple_sign_in_plugin) | [![pub points](https://img.shields.io/pub/points/apple_sign_in_plugin)](https://pub.dev/packages/apple_sign_in_plugin/score) | [![downloads](https://img.shields.io/pub/dm/apple_sign_in_plugin)](https://pub.dev/packages/apple_sign_in_plugin/score) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20apple_sign_in_plugin?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20apple_sign_in_plugin) |
| [attachment_engine](./packages/attachment_engine/attachment_engine/) | [![pub package](https://img.shields.io/pub/v/attachment_engine.svg)](https://pub.dev/packages/attachment_engine) | [![pub points](https://img.shields.io/pub/points/attachment_engine)](https://pub.dev/packages/attachment_engine/score) | [![downloads](https://img.shields.io/pub/dm/attachment_engine)](https://pub.dev/packages/attachment_engine/score) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20attachment_engine?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20attachment_engine) |
| [dig_cli](./packages/dig_cli/) | [![pub package](https://img.shields.io/pub/v/dig_cli.svg)](https://pub.dev/packages/dig_cli) | [![pub points](https://img.shields.io/pub/points/dig_cli)](https://pub.dev/packages/dig_cli/score) | [![downloads](https://img.shields.io/pub/dm/dig_cli)](https://pub.dev/packages/dig_cli/score) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20dig_cli?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20dig_cli) |
| [white_label_kit](./packages/white_label_kit/) | [![pub package](https://img.shields.io/pub/v/white_label_kit.svg)](https://pub.dev/packages/white_label_kit) | [![pub points](https://img.shields.io/pub/points/white_label_kit)](https://pub.dev/packages/white_label_kit/score) | [![downloads](https://img.shields.io/pub/dm/white_label_kit)](https://pub.dev/packages/white_label_kit/score) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20white_label_kit?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20white_label_kit) |

## Development & Tooling

This monorepo uses repository-level tooling based on `script/tool`:

```bash
# Set repository root
export REPO_ROOT=$(pwd)

# Format all code
dart run $REPO_ROOT/script/tool/bin/flutter_plugin_tools.dart format

# Run static analysis (zero warnings/infos)
dart run $REPO_ROOT/script/tool/bin/flutter_plugin_tools.dart analyze

# Run unit tests across all packages
dart run $REPO_ROOT/script/tool/bin/flutter_plugin_tools.dart dart-test

# Verify package publishability
dart run $REPO_ROOT/script/tool/bin/flutter_plugin_tools.dart publish-check --allow-pre-release
```

## Contributing

Please review the [contribution guide](CONTRIBUTING.md) and submit a pull request on [GitHub](https://github.com/dhc-tech/flutter-packages/pulls).

## Issues & Support

File issues, feature requests, and bug reports in our [issue tracker](https://github.com/dhc-tech/flutter-packages/issues).

## Authors & Maintainers

- **Digvijaysinh Chauhan** ([@dhc-tech](https://github.com/dhc-tech)) - Lead Architect & Author (`Digvijaysinh2204@gmail.com`)
- **DHC Tech**

## License

This project is licensed under the [MIT License](LICENSE).
