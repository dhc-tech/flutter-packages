# Agent Guide

Guidance for AI agents and contributors working in `dhc-tech/flutter-packages`.
Human-oriented details live in [CONTRIBUTING.md](CONTRIBUTING.md) and
[README.md](README.md); this file only adds what agents need to act safely.

## Rules

- Format with `dart format .`, then run `dart analyze --fatal-infos` and the
  affected tests. A change is not done until all three pass.
- Do not bump versions or edit `CHANGELOG.md` by hand; Melos generates them from
  Conventional Commit titles (`fix(pkg): ...`, `feat(pkg): ...`).
- Comments explain *why*, never restate the code.
- Never commit credentials or proprietary names.

## Layout

This is a pub workspace. The root `pubspec.yaml` lists every package and example
app; each member has `resolution: workspace`. Run `flutter pub get` once at the
root. Never add `dependency_overrides` or `pubspec_overrides.yaml` to a member.

- `packages/dig_cli`, `packages/white_label_kit` — standalone Dart packages.
- `packages/apple_sign_in_plugin/*`, `packages/attachment_engine/*` — federated
  plugins: app-facing package, `_platform_interface`, and one package per
  platform. Interface changes usually need matching implementation changes.

## Commands

```bash
flutter pub get                                  # resolve the workspace
dart format .                                    # or: melos run format
dart analyze --fatal-infos                       # or: melos run analyze
melos run publish:check                          # pub publish --dry-run everywhere
.github/scripts/run_tests.sh [package_dir ...]   # all packages, or just those given
dart run pigeon --input pigeons/<file>.dart      # after editing a pigeons/ file
dart run build_runner build -d                   # after changing build_runner inputs
```

`*_web` packages only load in a browser; the test script runs them with
`--platform chrome`.

## Releases

`release_pr.yml` runs `melos version` on `main` and maintains a `release/next` PR;
merging it triggers `release.yml`, which runs `.github/scripts/publish_changed.sh`
to publish packages whose `version:` changed and tag them `<name>-v<version>`.
Preview with `melos run version:preview` (discard the changes afterwards) or
`DRY_RUN=1 BASE_SHA=origin/main~1 .github/scripts/publish_changed.sh`.
See [docs/release_architecture.md](docs/release_architecture.md).
