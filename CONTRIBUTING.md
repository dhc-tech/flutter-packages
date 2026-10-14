# Contributing

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) first.

Thanks for helping improve the DHC Tech Flutter packages. This guide covers
everything needed to land a change in this monorepo.

## Setup

1. Install Flutter `3.47.7` or newer.
2. From the repository root, resolve the whole workspace once ([Melos](https://melos.invertase.dev/)
   is a workspace dev dependency, so `dart run melos <cmd>` works without a global install):

   ```bash
   flutter pub get
   git config core.hooksPath .githooks   # formats staged Dart files on commit
   ```

The root `pubspec.yaml` is a [pub workspace](https://dart.dev/tools/pub/workspaces):
every package and example app is a member, so sibling packages (for example
`attachment_engine` and `attachment_engine_android`) always resolve to the local
source. Do not add `dependency_overrides` or `pubspec_overrides.yaml` files to
packages; workspace members must declare `resolution: workspace`.

## Repository structure

- `packages/<name>/` — a standalone package (`dig_cli`, `white_label_kit`).
- `packages/<name>/<name>*/` — a federated plugin: the app-facing package
  `<name>`, `<name>_platform_interface`, and one `<name>_<platform>` package per
  platform. A change to the platform interface usually needs matching changes in
  the implementations.

## Before opening a PR

```bash
melos run format
melos run analyze
melos run test        # or: .github/scripts/run_tests.sh packages/<package>
```

CI (`validate`) runs the same checks plus `dart pub publish --dry-run` for every
package.

- PR titles follow [Conventional Commits](https://www.conventionalcommits.org/),
  for example `fix(dig_cli): handle missing pubspec`.
- Add or update tests for behavior changes.
- Add `///` documentation for public API (`public_member_api_docs` is enabled).
- Regenerate code when you change its inputs: `dart run pigeon --input pigeons/<file>.dart`
  for Pigeon definitions, `dart run build_runner build -d` for packages using
  `build_runner`.

## Versioning and changelogs

Versions are never bumped automatically. Release a package deliberately, in the
same PR as the change (or a follow-up PR) that touches its non-test code:

1. Bump `version:` in that package's `pubspec.yaml` ([semantic versioning](https://semver.org/):
   patch for fixes, minor for features or public API additions, major for breaking changes).
2. Add a matching entry at the top of that package's `CHANGELOG.md`.

Changes that should not release (docs, tests, CI) leave the version alone.
Merging a version bump to `main` publishes that package. For federated plugins,
bump the platform interface and implementations together when the interface
changes. See [docs/release_architecture.md](docs/release_architecture.md).

## Labels

Labels are applied automatically from your PR title and changed files, so you
normally do not set any. See [docs/labels.md](docs/labels.md) for what each label
means, which ones maintainers add (`autosubmit`, `good first issue`,
`help wanted`, ...) and how to read the `status:*` labels.

## Merging

Once a PR is approved and every check is green it gets the `status: ready` label.
A maintainer adds the `autosubmit` label to squash-merge it automatically; the
label is removed if checks fail or changes are requested. Dependabot PRs are
handled separately by `dependabot-auto-merge.yml`. If a GitHub merge queue is
enabled for `main`, `validate` already runs on `merge_group` events.

## Review

PRs are assigned to [code owners](.github/CODEOWNERS) automatically. Code owners
opening a PR should request review from another team member.
