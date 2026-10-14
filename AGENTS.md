# Agent Guide for the DHC Tech Flutter Packages Repository

This document provides guidance for AI agents to effectively contribute to the `dhc-tech/flutter-packages` repository.

## Guiding Principles for Contributions

- **Format All Code**: Every code change must be formatted using the repository's tools.
- **Pass All Tests**: All changes must pass linting, analysis, and relevant tests.
- **Update CHANGELOGs**: Any user-facing change or bug fix in a package requires an update to its `CHANGELOG.md` and `pubspec.yaml` version. Ensure you follow the [CHANGELOG style guide](https://github.com/flutter/flutter/blob/master/docs/ecosystem/contributing/README.md#changelog-style).
- **Follow Conventions**: Adhere to the repository's specific conventions, such as federated plugin structure and code generation steps.

## Agent Environment Setup

To ensure a consistent and functional environment, configure your VM with the following setup. This provides the necessary Flutter SDK and dependencies for building and testing packages.

```bash
curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz | tar -xJ -C $HOME
export FLUTTER_HOME=$HOME/flutter
export PATH=$FLUTTER_HOME/bin:$PATH
flutter --disable-analytics
flutter precache --force
# Sanity check the configuration.
flutter doctor --verbose
```

## Repository Overview

This is a monorepo containing Flutter packages maintained by DHC Tech.
- First-party packages developed by DHC Tech are in `packages/`.
- All first-party packages are in `packages/`.

Many packages are part of **federated plugins**. A federated plugin has a main package (e.g., `apple_sign_in_plugin`) that defines the API used by plugin clients, a platform interface package (e.g., `apple_sign_in_plugin_platform_interface`) that defines the interface that each platform implementation must implement, and one or more platform implementation packages (e.g., `apple_sign_in_plugin_ios`, `apple_sign_in_plugin_web`) that implement that platform interface. When working on a federated plugin, you may need to modify multiple packages.

For more details, see the main `README.md` and `CONTRIBUTING.md`.

## Core Tooling and Workflows

This repository uses standard Flutter and Dart SDK tools for development, testing, and validation.

### Formatting

Always format your code changes:
```bash
dart format .
```

### Static Analysis

Run analysis across all packages:
```bash
dart analyze --fatal-infos
```

### Running Tests

Run unit and widget tests:
```bash
# Run tests for a specific package:
flutter test packages/<package_name>

# Run all tests across the repository:
for pkg in $(find packages -mindepth 1 -maxdepth 2 -name pubspec.yaml -exec dirname {} \; | sort); do
  if [ -d "$pkg/test" ]; then
    echo "Running tests in $pkg"
    (cd "$pkg" && flutter test)
  fi
done
```

## Code Generators

Some packages use code generators, and changes to those packages require running the relevant code generators.

- **Pigeon**: If you change a file in a `pigeons/` directory, you must run the Pigeon generator:
  ```bash
  # Run from the package's directory
  dart run pigeon --input pigeons/<changed_file>.dart
  ```
- **Mockito**: If you change code in a package that uses `mockito` for tests (check `dev_dependencies` in `pubspec.yaml`), you must run its mock generator:
  ```bash
  # Run from the package's directory
  dart run build_runner build -d
  ```

## Code Style

All code must adhere to the repository's style guides. The `format` command handles most of this, but be aware of the specific style guides for each language, as detailed in [CONTRIBUTING.md](./CONTRIBUTING.md#style):
- **Dart**: Flutter style, formatted with `dart format`.
- **C++**: Google style, formatted with `clang-format`.
- **Java**: Google style, formatted with `google-java-format`.
- **Kotlin**: Android Kotlin style, formatted with `ktfmt`.
- **Objective-C**: Google style, formatted with `clang-format`.
- **Swift**: Google style, formatted with `swift-format`.
- **Comments**: Avoid adding redundant or trivial comments that simply restate what the code itself does (e.g., repeating method calls in English). Comments should explain the *why* behind complex or non-obvious logic, or serve as public API documentation.

## Version and CHANGELOG updates

Any PR that changes non-test code in a package should update its version in pubspec.yaml and add a corresponding entry in CHANGELOG.md.

**This process can be automated**. The `update-release-info` command is the preferred way to handle this. It determines changed packages, bumps versions, and updates changelogs automatically.
```bash
dart run $REPO_ROOT/script/tool/bin/flutter_plugin_tools.dart update-release-info \
  --version=minimal \
  --base-branch=origin/main \
  --changelog="A description of the changes."
```

- `--version=minimal`: Bumps patch for bug fixes, and skips unchanged packages. This is usually the best option unless a new feature is being added.
  - When making public API changes, use `--version=minor` instead.
- `--base-branch=origin/main`: Diffs against the `main` branch to find changed packages.

If you update manually, follow semantic versioning and the [repository's CHANGELOG style](https://github.com/flutter/flutter/blob/master/docs/ecosystem/contributing/README.md#changelog-style).
