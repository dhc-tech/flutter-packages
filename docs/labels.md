# Labels

Labels make issues and pull requests easy to find and drive the merge
automation. **Most are applied automatically**; this page says which ones, when
to apply the rest, and what each one does. Names, colors and descriptions live
in [`.github/labels.json`](../.github/labels.json) and are synced to the
repository by the `Sync Labels` workflow.

## Naming convention

Every label belongs to a group and is written `group: value`:

| Group | Answers | Applied by |
|---|---|---|
| `p: <package>` | Which package family? | Automatic (changed files / issue text) |
| `platform: <name>` | Which platform implementation? | Automatic (changed files / issue text) |
| `type: <kind>` | What kind of change? | Automatic (PR title) or issue template |
| `status: <state>` | Where is this PR? | Automatic only |
| `needs: <what>` | What is it waiting for? | Template, then maintainers |
| `infra: <area>` | CI or dependency work | Automatic |

A few standalone labels have a fixed meaning: `breaking-change`, `documentation`,
`autosubmit`, `good first issue`, `help wanted`, `question`, `duplicate`,
`invalid`, `wontfix`, `stale`.

## Pull requests

**You do not need to label a pull request.** Write the title as a
[Conventional Commit](https://www.conventionalcommits.org/) (`fix(dig_cli): ...`)
and the labels below are applied for you. Do not add `status:` labels by hand;
they are recomputed on every push.

| Label | When it appears | What to do |
|---|---|---|
| `p: apple_sign_in_plugin`, `p: attachment_engine`, `p: dig_cli`, `p: white_label_kit` | Your PR changes files in that package family | Nothing. |
| `platform: android` / `ios` / `macos` / `darwin` / `linux` / `windows` / `web` / `interface` | Your PR changes a `*_<platform>` package | Nothing. |
| `type: feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` | From the PR title prefix | Fix the title if it is wrong. |
| `breaking-change` | Title has `!` or the body has a `BREAKING CHANGE` footer | Describe the migration in the PR. |
| `status: needs-review` | Waiting for a review or running checks | Wait, or request a reviewer. |
| `status: changes-requested` | A reviewer asked for changes | Push fixes; it clears itself. |
| `status: ci-failed` | A required check is failing | Open the failing check and fix it. |
| `status: blocked` | Draft or merge conflicts | Mark ready for review or rebase. |
| `status: ready` | Approved and all checks green | Nothing; it can be merged. |
| `autosubmit` | **Maintainer adds it** | Squash-merges the PR as soon as it is `status: ready`; removed automatically if checks fail or changes are requested. |
| `infra: workflows`, `documentation` | Your PR changes `.github/` or markdown | Nothing. |
| `infra: dependencies` | Dependabot opened the PR | Nothing. |

## Issues

Opening an issue from a template adds `type: fix` or `type: feat` and
`needs: triage`. A maintainer or triager then labels it:

| Label | Who adds it | When |
|---|---|---|
| `needs: triage` | Template (automatic) | New issue nobody has looked at yet. Remove it once triaged. |
| `p: <package>`, `platform: <name>` | Automatic from the text; triager corrects it | Which package or platform is affected. |
| `type: fix` / `type: feat` | Template; triager corrects it | Bug versus feature request. |
| `needs: info` | Triager | Reporter must add a version, repro steps or logs. Remove it when they reply. |
| `good first issue` | Triager | Small, well-scoped, safe for newcomers. |
| `help wanted` | Triager | We welcome a contribution; ask to be assigned before starting. |
| `question` | Triager | A usage question, not a bug; answer and close. |
| `duplicate`, `invalid`, `wontfix` | Triager | Closing reasons; always leave a comment saying why. |
| `stale` | Automatic | No activity for a long time; closes if nobody responds. |

## Triage checklist (maintainers and triagers)

1. Read the issue and remove `needs: triage`.
2. Make sure `p:` and `platform:` are right and add `type: fix` or `type: feat`.
3. Not enough detail? Add `needs: info` and ask for what is missing.
4. Not a bug or already tracked? Add `question`, `duplicate`, `invalid` or
   `wontfix`, comment why, and close.
5. Worth fixing but not by you? Add `help wanted`, plus `good first issue` if it
   is beginner friendly.

## Merging (maintainers)

When a PR is `status: ready`, add `autosubmit` to squash-merge it hands-free.
Do not add it to PRs that should wait for a version bump, a release window or
another PR. Dependabot PRs are handled by `dependabot-auto-merge.yml`.

## Changing labels

Edit `.github/labels.json` (the workflow syncs it on `main`). Path-based rules
live in `.github/labeler.yml`, issue-text rules in `.github/workflows/issue-labeler.yml`,
and `type` / `status` logic in `.github/workflows/pr-metadata.yml`.
