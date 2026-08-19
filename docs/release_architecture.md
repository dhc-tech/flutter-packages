# Release Architecture

Layered, PR-gated release workflows with independent per-package
versioning, sized for this repo's actual scope (3 packages).

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
| Package publishing | `publish.yml` | Triggered by a package release tag: validates, then publishes that one package to pub.dev via stored PUB_CREDENTIALS. |

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
- Authenticated via a stored `PUB_CREDENTIALS` repo secret — the same
  mechanism [flutter/packages' own release pipeline](https://github.com/flutter/packages)
  uses (their custom publish tool reads a `PUB_CREDENTIALS` secret and
  writes it to pub's credentials file before calling `dart pub
  publish`; this repo's `publish.yml` does the equivalent directly).
  Not pub.dev's OIDC "Automated publishing" feature — that needs a
  one-time, human-only opt-in on each package's pub.dev admin page
  before it does anything, and without it `dart pub publish` silently
  falls back to an interactive Google OAuth prompt that hangs forever
  in CI (confirmed on a real run, before switching to this approach)
- Before any real publish: validates `publish_to: none` isn't set, the
  tag's version matches `pubspec.yaml`'s version, `CHANGELOG.md` has an
  entry for that version, and that the version isn't already published
  — then always runs `dart pub publish --dry-run` before the real
  publish

### One-time setup: generating `PUB_CREDENTIALS` (per pub.dev account, not per package)

A human with publish rights to all 3 packages runs, once, on their own
machine:

```
dart pub login
```

This opens a browser for a normal Google OAuth login and writes a
credentials file to `~/.config/dart/pub-credentials.json` (Linux) or
`~/Library/Application Support/dart/pub-credentials.json` (macOS).
Copy that file's entire contents into a repository secret named
`PUB_CREDENTIALS` (Settings → Secrets and variables → Actions → New
repository secret). `publish.yml` writes it back out to the same path
on the runner before every publish — no pub.dev admin-page
configuration needed at all, and it authorizes all packages this
account can publish, not just one.

## What was deliberately not built

- **A separate `sync_release_pr.yml`** — `release.yml` already
  re-syncs an open release PR every time it fires (via
  `reusable_release.yml`'s existing-open-PR detection), so a standalone
  file would just duplicate that.
- **Per-package batch workflows** (e.g. `dig_cli_batch.yml`) — every
  release path already accepts any package by name, with zero workflow
  changes needed to add a new package. A dedicated per-package workflow
  would add files without adding capability.
- **A dedicated release dashboard/tracking service** — built for a
  much larger, higher-traffic monorepo; not proportionate here.
