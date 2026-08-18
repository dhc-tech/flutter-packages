# Release Architecture

This repository's release system is modeled on [flutter/packages](https://github.com/flutter/packages)'
architectural principles — layered, PR-gated release workflows with
independent per-package versioning — sized for this repo's actual scope
(3 packages), not a copy of flutter/packages' Cocoon/dashboard-scale
infrastructure.

## Why packages are versioned independently

`white_label_kit`, `dig_cli`, and `apple_sign_in_plugin` are separate
pub.dev packages with separate consumers and separate release cadences.
A fix in `dig_cli` has no reason to bump `white_label_kit`'s version —
doing so would be noise for that package's consumers and would
misrepresent what actually changed. [Melos](https://melos.invertase.dev/)
computes each package's version from its own conventional-commit history
since its own last release tag, independently.

## Workflow responsibility map

| Layer | File | Responsibility |
|---|---|---|
| Release preparation (automatic) | `release.yml` | On every merge to `main` touching `packages/**`, prepare a release PR if any package needs one. |
| Release preparation (batch) | `batch_release_pr.yml` | Manual (`workflow_dispatch`): prepare a release PR for a chosen set of packages, or all of them. |
| Release preparation (branch) | `release_from_branches.yml` | Manual: prepare a release PR from a ref other than `main` (e.g. a hotfix branch). |
| Shared release logic | `reusable_release.yml` | The one implementation all three callers above use — melos version/changelog computation, release-branch creation, opening (or updating) the release PR. Not called directly. |
| Final release / tagging | `release_tag_on_merge.yml` | Once a `chore(release): ...` PR merges to `main`, create and push the real `<package>-vX.Y.Z` tag(s). |
| Package publishing | `publish.yml` | Triggered by a package release tag: validates, then publishes that one package to pub.dev via OIDC. |

## Normal flow (single or multiple packages)

```
PR (feature/fix)
  → CI + review + AI review
  → merge to main
  → release.yml prepares/updates a release PR
    (independently versions every package with release-worthy commits)
  → release PR gets CI + review like any other change
  → release PR merges to main
  → release_tag_on_merge.yml pushes one tag per released package
  → publish.yml runs once per tag, publishing that package only
```

If only `dig_cli` has release-worthy commits, the release PR contains
only `dig_cli`'s version bump + changelog — `white_label_kit` and
`apple_sign_in_plugin` are untouched. If several packages changed, the
same PR contains all of them, each with its own version.

## Batch flow (manual)

```
maintainer runs batch_release_pr.yml (packages: "all" or a list)
  → reusable_release.yml prepares one release PR
    covering exactly the requested packages, each independently versioned
  → release PR gets CI + review
  → merges
  → release_tag_on_merge.yml tags each released package
  → publish.yml publishes each, independently
```

A batch release is "release these together," never "give them all the
same version."

## Why release PRs, not a direct push to `main`

Branch protection requires every change to `main` to go through a pull
request — including release commits. This was the actual root cause of
an early release attempt failing outright ("Changes must be made
through a pull request"), while the tags it also pushed were *not*
rejected (tags aren't the protected `main` ref), leaving orphaned tags
pointing at commits never on `main`. The fix: release commits go
through the exact same PR + CI + review gate as any other change.
Tags are only created in a later, separate stage, once the release
commit is actually on `main`.

## Package tags

Format: `<package-name>-v<version>` (e.g. `dig_cli-v1.9.0`). Never a
single global version tag. `release_tag_on_merge.yml` checks each tag's
existence before creating it — a rerun never duplicates or overwrites
one.

## Pub.dev publishing

- Triggered by a package's release tag (`publish.yml`)
- One tag = one package = one isolated workflow run — a batch release
  producing 3 tags produces 3 independent publish runs; one package's
  failure has no effect on the others
- Authenticated via [pub.dev automated publishing](https://dart.dev/tools/pub/automated-publishing)
  (GitHub Actions OIDC, `permissions: id-token: write`) — no stored
  credentials, no PAT
- Before any real publish: validates `publish_to: none` isn't set, the
  tag's version matches `pubspec.yaml`'s version, `CHANGELOG.md` has an
  entry for that version, and that the version isn't already published
  — then always runs `dart pub publish --dry-run` before the real
  publish

### One-time manual pub.dev configuration (per package)

On each package's `pub.dev/packages/<name>/admin` page → Automated
publishing:
- Repository: `dhc-tech/flutter-packages`
- Tag pattern: `<name>-v{{version}}`
- Enable publishing from GitHub Actions + push events

## What was deliberately not built

- **A separate `sync_release_pr.yml`** — `release.yml` already
  re-syncs an open release PR every time it fires (via
  `reusable_release.yml`'s existing-open-PR detection), so a standalone
  file would just duplicate that.
- **Per-package batch workflows** (e.g. `dig_cli_batch.yml`) — every
  release path already accepts any package by name, with zero workflow
  changes needed to add a new package. A dedicated per-package workflow
  would add files without adding capability.
- **Flutter's Cocoon/dashboard infrastructure** — built for a much
  larger, higher-traffic monorepo; not proportionate here.
