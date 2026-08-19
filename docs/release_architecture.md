# Release Architecture

Layered release workflows with independent per-package versioning,
sized for this repo's actual scope (3 packages). The publish/tag stage
is a literal structural clone of
[flutter/packages](https://github.com/flutter/packages)' own
`release.yml` + `script/tool` architecture (see
`docs/flutter_packages_clone_notes.md` if present, or the PR that
introduced this file, for the full clone rationale).

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
| Release preparation (automatic) | `release.yml`'s `prepare` job | On every merge to `main` touching `packages/**` that isn't itself a release-prep merge, prepare a release PR if any package needs one. This stage is this repo's own addition — flutter/packages assumes a human/PR already bumped `pubspec.yaml`/`CHANGELOG.md` before their `release.yml` runs; `script/tool`'s `publish` command does not compute version bumps itself (confirmed from source, see below). |
| Release preparation (batch) | `batch_release_pr.yml` | Manual (`workflow_dispatch`): prepare a release PR for a chosen set of packages, or all of them. |
| Release preparation (branch) | `release_from_branches.yml` | Manual: prepare a release PR from a ref other than `main` (e.g. a hotfix branch). |
| Shared release logic | `reusable_release.yml` | The one implementation all three callers above use — melos version/changelog computation, release-branch creation, opening (or updating) the release PR. Not called directly. |
| Publish + tag (automatic, atomic) | `release.yml`'s `publish` job | Once a `chore(release): ...` PR merges to `main`, waits for CI (`CI Success`), then runs flutter/packages' own vendored `script/tool` CLI: `dart ./script/tool/lib/src/main.dart publish --all-changed --base-sha=HEAD~ --skip-confirmation --remote=origin`. This one command publishes every package whose pubspec version changed to pub.dev (via `PUB_CREDENTIALS`), tags the release, and pushes the tag — atomically. |

This is exactly flutter/packages' own architecture: their `release.yml`
runs on every push to `main` and does the entire publish+tag+push in
one job via `script/tool`'s `publish` command — there is no separate
tag-creation workflow and no separate per-tag publish workflow
upstream. `script/tool/lib/src/publish_command.dart` (vendored verbatim
under `script/tool/`) documents the command as:

> Wraps pub publish with a few niceties used by the flutter/plugin team.
> 1. Checks for any modified files in git and refuses to publish if
>    there's an issue.
> 2. Tags the release with the format `<package-name>-v<package-version>`.
> 3. Pushes the release to a remote.

It does **not** compute version bumps itself — it expects
`pubspec.yaml`/`CHANGELOG.md` to already be bumped in the commit it's
publishing (via `update-release-info`, a separate `script/tool`
command not wired into automatic CI here), which is exactly what this
repo's melos-based `prepare` job (stage 1, unchanged by this clone)
provides.

The old `release_tag_on_merge.yml` (separate tag-creation workflow) and
`publish.yml` (tag-triggered, pub.dev-OIDC publish workflow) have been
**removed**. Both are fully superseded by `script/tool`'s `publish`
command, which does tagging, pushing, and pub.dev publishing (via
stored `PUB_CREDENTIALS`, never OIDC) atomically in one process.
Keeping them alongside the new `release.yml` publish job would have
left two competing publish paths for the same event.

## Normal flow (single or multiple packages)

```
PR (feature/fix)
  → CI + review + AI review
  → merge to main
  → release.yml's `prepare` job opens/updates a release PR
    (independently versions every package with release-worthy commits)
  → release PR gets CI + review like any other change
  → release PR merges to main (commit message contains "chore(release):")
  → release.yml's `publish` job runs: waits for CI, then invokes
    script/tool's `publish --all-changed` once, which for every package
    whose pubspec version changed: publishes to pub.dev, tags the
    release, and pushes the tag — atomically, in one process
```

If only `dig_cli` has release-worthy commits, the release PR contains
only `dig_cli`'s version bump + changelog — `white_label_kit` and
`apple_sign_in_plugin` are untouched. If several packages changed, the
same PR contains all of them, each with its own version, and the single
`publish --all-changed` invocation handles all of them in one run.

## Batch flow (manual)

```
maintainer runs batch_release_pr.yml (packages: "all" or a list)
  → reusable_release.yml prepares one release PR
    covering exactly the requested packages, each independently versioned
  → release PR gets CI + review
  → merges (commit message contains "chore(release):")
  → release.yml's `publish` job runs `publish --all-changed` once,
    publishing + tagging + pushing every changed package
```

A batch release is "release these together," never "give them all the
same version."

## Why release PRs, not a direct push to `main`

Branch protection requires every change to `main` to go through a pull
request — including release commits. This was the actual root cause of
an early release attempt failing outright ("Changes must be made
through a pull request"). The fix: release commits go through the
exact same PR + CI + review gate as any other change. Tagging now
happens only after that commit is actually on `main`, as part of the
same `publish` job that publishes to pub.dev — never before, and never
as a separate stage.

## Package tags

Format: `<package-name>-v<version>` (e.g. `dig_cli-v1.9.0`). Never a
single global version tag. `script/tool`'s `publish` command checks
each tag's existence in the repository before creating it — a rerun of
`release.yml`'s `publish` job never duplicates or overwrites one.

## Pub.dev publishing

- Runs as part of `release.yml`'s `publish` job, on every push to
  `main` whose commit message contains `chore(release):` — mirrors
  flutter/packages' own `release.yml`, which runs its publish job on
  every push to `main` (script/tool's own change-detection then skips
  packages with nothing new to publish).
- `--all-changed` handles any number of changed packages in one
  invocation; a batch release producing 3 changed packages still runs
  as a single `publish` command call.
- Authenticated via **`PUB_CREDENTIALS`, a stored repository secret**,
  read by `script/tool`'s `publish` command — **not** pub.dev OIDC,
  and no `id-token: write` permission anywhere in the workflow. This is
  the literal flutter/packages auth mechanism, not a substitute.
- `script/tool`'s `publish` command performs its own pre-publish
  checks (already-published detection, git-tag collision checks) as
  part of the same process — no separate dry-run/validation workflow
  step is needed here, because that logic lives inside the vendored
  tool itself.

### One-time manual pub.dev configuration (per package)

`PUB_CREDENTIALS` must be populated with valid pub.dev publishing
credentials (see `dart pub token` / `dart pub publish` credential
docs) and stored as the `PUB_CREDENTIALS` repository secret. No
pub.dev "Automated publishing"/OIDC configuration is used or required.

## `.repo_tool_config.yaml`: not required

flutter/packages' `script/tool` reads an optional
`.repo_tool_config.yaml` at the repo root (`common/tool_config.dart`,
`configFilename`). Reading that source directly: the config is only
ever loaded by `getRepositoryName`, `getMinFlutterVersion`,
`getMinDartVersion`, `getAllowedDependencies`, and
`getNonStandardPackageLabels` — and those are called exclusively from
`repo_info_validator.dart`, `pubspec_validator.dart`, and
`validate_command.dart` (the `validate-repo-info` / dependency-check
paths of the `validate` command). This repo's only wired `script/tool`
invocation is `release.yml`'s `publish --all-changed` (see above),
which never touches `tool_config.dart`. So the file is not required
for this repo's actual usage, and was deliberately not added — it
would be a cosmetic file with no effect until/unless a future PR wires
up `validate --enforce-*`/`validate-repo-info` from this vendored tool.

## What was deliberately not built

- **A separate `sync_release_pr.yml`** — flutter/packages' own
  `sync_release_pr.yml` exists only to sync federated/batched-release
  branches (`release-go_router-*`, `release-cupertino_ui-*`,
  `release-material_ui-*`) back to `main`; none of this repo's 3
  packages are federated plugins using that batch-branch convention,
  so it has no equivalent need here. `release.yml`'s `prepare` job
  already re-syncs an open release PR every time it fires (via
  `reusable_release.yml`'s existing-open-PR detection).
- **Per-package batch workflows** (e.g. `dig_cli_batch.yml`) — every
  release path already accepts any package by name, with zero workflow
  changes needed to add a new package. A dedicated per-package workflow
  would add files without adding capability.
- **A dedicated release dashboard/tracking service** — built for a
  much larger, higher-traffic monorepo; not proportionate here.
- **`remove_cicd.yml`** — upstream removes a stale `CICD` label that
  is meaningful only in flutter/packages' Google-internal LUCI/Cocoon
  CI integration (a label that re-triggers/reflects a Cocoon dispatch
  and must be cleared on every new push). This repo's CI is plain
  GitHub Actions (`ci.yml`), triggered automatically on every push
  with no Cocoon-style manual re-trigger label at all, so there is no
  `CICD` label to ever go stale. Confirmed by reading the workflow
  (2026-08-19): its only job is removing that one specific label name.
- **`post_merge_labeler.yml`** — upstream's `pull_request_label.yml`
  references a second config, `.github/post_merge_labeler.yml`, applied
  only on the PR's `closed` (merge) event, for labels that are only
  meaningful after merge lands. It is not Cocoon/federation-specific,
  but this repo's `pull_request_label.yml` only fires on
  `opened`/`synchronize`/`reopened` and that is sufficient here: every
  label this repo's automation depends on (`p: <package>`,
  `infra: workflows`, `infra: dependencies`) is read by pre-merge
  automation (AI review path instructions, Dependabot grouping, PR
  labeling itself) and by nothing that only runs post-merge. Adding a
  `closed`-triggered duplicate config would relabel nothing new.
