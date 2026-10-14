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
  → `release` workflow waits for `validate` on the merge commit
  → .github/scripts/publish_changed.sh
      for every package whose `version:` differs from the previous commit:
        dart pub publish --force, then tag <package>-v<version>
```

A change without a version bump merges normally and publishes nothing; it ships
with the package's next bump.

## Components

| File | Responsibility |
|---|---|
| `.github/workflows/validate.yml` | Required check on PRs and `main`: formatting, analysis, tests, publish dry-run for every package. |
| `.github/workflows/release.yml` | Runs on push to `main` (or manually). Waits for `validate`, then publishes. |
| `.github/scripts/run_tests.sh` | Runs each package's tests; pure Dart packages use `dart test`, `*_web` packages use `flutter test --platform chrome`. |
| `.github/scripts/publish_changed.sh` | Detects version changes, publishes in dependency order, tags and pushes. |
| `.github/workflows/internals/install_flutter` | Installs the pinned Flutter version (`3.47.7`) shared by all workflows. |

## Publish order

Federated plugins are published in three stages so dependencies exist on pub.dev
before their dependents: `*_platform_interface`, then platform implementations
(`*_android`, `*_web`, ...), then the app-facing package. Standalone packages
(`dig_cli`, `white_label_kit`) publish in the last stage.

## Tags

`<package>-v<version>`, for example `dig_cli-v1.8.2`. A tag that already exists
is skipped, so re-running the workflow never duplicates or overwrites one.

## Manual and recovery runs

- Re-run `release` from the Actions tab with `base-sha` set to publish bumps that
  merged while the workflow was failing. The base commit is compared to `HEAD`.
- Preview locally without publishing:

  ```bash
  DRY_RUN=1 BASE_SHA=origin/main~1 .github/scripts/publish_changed.sh
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
