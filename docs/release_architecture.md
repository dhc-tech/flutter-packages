# Release Architecture

Every package is versioned and published independently. A package is released
by changing its `version:` in `pubspec.yaml` and merging to `main`; there is no
separate release PR, tool or tag workflow.

## Flow

Every package is versioned independently and by hand. Nothing bumps a version
automatically, so an unrelated change can never trigger a release.

```text
PR (code + deliberate `version:` bump + CHANGELOG entry)
  → `validate` workflow: format, analyze, tests, `dart pub publish --dry-run`
  → merge to main
  → `release` workflow (push to main, hourly, or manual)
  → .github/scripts/publish_unpublished.sh
      for every package whose `version:` is not on pub.dev yet:
        dart pub publish --force, then tag <package>-v<version>
```

A change without a version bump merges normally and publishes nothing; it ships
with the package's next bump. Because the script compares against pub.dev rather
than a git diff, a skipped or half-finished run is completed by the next one, and
merges that do not trigger `push` workflows (auto-merge with the default
`GITHUB_TOKEN`) are still released by the hourly run. No extra token is needed.

## Components

| File | Responsibility |
|---|---|
| `.github/workflows/validate.yml` | Required check on PRs and `main`. Runs the steps of `.github/scripts/ci.sh`: formatting, analysis, script and workflow tests, package tests, publish dry-run. |
| `.github/scripts/ci.sh` | The validate pipeline as one script; `ci.sh local` runs it on a clean clone of the committed HEAD. |
| `.github/workflows/release.yml` | Runs on push to `main` (or manually). Waits for `validate`, then publishes. |
| `.github/scripts/run_tests.sh` | Runs each package's tests; pure Dart packages use `dart test`, `*_web` packages use `flutter test --platform chrome`. |
| `.github/scripts/publish_unpublished.sh` | Finds package versions missing from pub.dev, publishes them in dependency order, tags and pushes. |
| `.github/actions/install_flutter` | Installs the pinned Flutter version (`3.47.7`) shared by all workflows. |

## Publish order

Federated plugins are published in three stages so dependencies exist on pub.dev
before their dependents: `*_platform_interface`, then platform implementations
(`*_android`, `*_web`, ...), then the app-facing package. Standalone packages
(`dig_cli`, `white_label_kit`) publish in the last stage.

## Tags

`<package>-v<version>`, for example `dig_cli-v1.8.2`. A tag that already exists
is skipped, so re-running the workflow never duplicates or overwrites one.

## Manual and recovery runs

- Run `release` from the Actions tab at any time; it only publishes what is missing.
- Preview locally without publishing:

  ```bash
  DRY_RUN=1 .github/scripts/publish_unpublished.sh
  ```

## Secrets

| Secret | Purpose |
|---|---|
| `PUB_CREDENTIALS` | pub.dev credentials JSON (contents of the file created by `dart pub login`). The script writes it to `$PUB_CACHE/credentials.json`. |
| `USER_NAME`, `USER_EMAIL` | Git identity used for tags. |

## Adding a package

1. Create it under `packages/` (federated plugins: `packages/<name>/<name>_<platform>`).
2. Add `resolution: workspace` to its `pubspec.yaml` and list its directory under
   `workspace:` in the root `pubspec.yaml`.
3. Add a row to the package table in `README.md`. A new package family also needs
   a `p: <family>` entry in `.github/labeler.yml`; platform packages are labeled
   automatically by their `_<platform>` suffix.
