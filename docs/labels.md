# Labels

Labels keep issues and pull requests easy to find and drive the merge
automation. Most are applied automatically; this page says which ones, when,
and by whom. The full list (names, colors, descriptions) lives in
[`.github/labels.json`](../.github/labels.json) and is synced to the repository
by the `Sync Labels` workflow when that file changes on `main`.

## Pull requests

You do not need to label a pull request. Make the **title** a
[Conventional Commit](https://www.conventionalcommits.org/) (`fix(dig_cli): ...`)
and everything below is applied for you.

| Label | Applied | Meaning |
|---|---|---|
| `p: apple_sign_in_plugin`, `p: attachment_engine`, `p: dig_cli`, `p: white_label_kit` | Automatically, from changed paths | Which package family the PR touches. |
| `platform: android` / `ios` / `macos` / `darwin` / `linux` / `windows` / `web` / `interface` | Automatically, from changed paths | Which platform implementation package the PR touches. |
| `type:feat`, `type:fix`, `type:docs`, ... | Automatically, from the PR title | Conventional Commit type of the change. |
| `breaking-change` | Automatically, from `!` in the title or a `BREAKING CHANGE` footer | Breaking change; the maintainer picks a major version bump when releasing. |
| `status:needs-review` | Automatically | Waiting for a review or for checks. |
| `status:changes-requested` | Automatically | A reviewer asked for changes. Push fixes; it clears itself. |
| `status:ci-failed` | Automatically | A required check is failing. Open the failing check and fix it. |
| `status:blocked` | Automatically | Draft or merge conflicts. Mark ready or rebase. |
| `status:ready` | Automatically | Approved and checks green. Merges automatically. |
| `autosubmit` | **Maintainers** | Squash-merges the PR as soon as it is `status:ready`. Removed automatically if checks fail or changes are requested. |
| `infra: workflows`, `documentation` | Automatically, from changed paths | CI or docs changes. |
| `infra: dependencies` | Automatically for Dependabot | Dependency update. |

## Issues

Opening an issue from a template adds `needs: triage` and a type label.
A maintainer then triages it:

| Label | Applied by | When |
|---|---|---|
| `needs: triage` | Template (automatic) | Waiting for a maintainer. Removed once triaged. |
| `p: <package>`, `platform: <name>` | Automatic from the issue text, or a maintainer | Which package or platform is affected. |
| `type:fix` / `type:feat` | Template or maintainer | Bug or feature request. |
| `needs: info` | Maintainer | The reporter must add details (version, repro steps, logs). |
| `good first issue` | Maintainer | Small, well-scoped, good for newcomers. |
| `help wanted` | Maintainer | Contributions are welcome; comment before starting. |
| `question` | Maintainer | A usage question rather than a bug. |
| `duplicate`, `invalid`, `wontfix` | Maintainer | Closing reasons; add a comment explaining why. |
| `stale` | Automatic | No activity for an extended period. |

## Contributors

- Pick issues labeled `good first issue` or `help wanted`.
- Name the package in your PR title; the rest is automatic.
- Do not add `autosubmit` yourself; maintainers use it to merge.

## Maintainers

- Triage new issues: replace `needs: triage` with the right labels.
- To merge a `status:ready` PR hands-free, add `autosubmit`.
- To add or change a label, edit `.github/labels.json`; the workflow syncs it.
  Path-based labels live in `.github/labeler.yml`, issue-text rules in
  `.github/issue-labeler.yml`, and type/status logic in
  `.github/workflows/pr-metadata.yml`.
