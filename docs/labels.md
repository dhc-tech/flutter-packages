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
| `status: <state>` | Where is this PR in review and CI? | Automatic only (`status: on hold` by maintainers) |
| `needs: <what>` | What is an issue waiting for? | Template, then maintainers |
| `infra: <area>` | CI or dependency work | Automatic |

A few standalone labels have a fixed meaning: `breaking-change`, `documentation`,
`good first issue`, `help wanted`, `question`, `duplicate`,
`invalid`, `wontfix`, `stale`.

## Pull requests

**You do not need to label a pull request.** Write the title as a
[Conventional Commit](https://www.conventionalcommits.org/) (`fix(dig_cli): ...`)
and the labels below are applied for you. A `status:` label always shows where the
PR is: you never set it, and it updates on every push, review and check result.

| Label | When it appears | What to do |
|---|---|---|
| `p: apple_sign_in_plugin`, `p: attachment_engine`, `p: dig_cli`, `p: white_label_kit` | Your PR changes files in that package family | Nothing. |
| `platform: android` / `ios` / `macos` / `darwin` / `linux` / `windows` / `web` / `interface` | Your PR changes a `*_<platform>` package | Nothing. |
| `type: feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` | From the PR title prefix | Fix the title if the type is wrong. |
| `breaking-change` | Title has `!` or the body has a `BREAKING CHANGE` footer | Describe the migration in the PR. |
| `infra: workflows`, `documentation` | Your PR changes `.github/` or markdown | Nothing. |
| `infra: dependencies` | Dependabot opened the PR | Nothing. |

### PR status lifecycle

Every open PR carries exactly one status label, kept up to date by
`.github/workflows/pr-status.yml`:

| Label | Meaning | What to do |
|---|---|---|
| `status: needs approval` | Not approved yet, a reviewer asked for changes, or the PR is a draft | Request a review, address feedback, or mark the draft ready. |
| `status: waiting for green` | Approved; checks are still running | Wait. |
| `status: ci failed` | Approved, but a check failed; merge is blocked | Open the failing check and push a fix. |
| `status: automerge` | Approved and every check green; squash auto-merge is enabled | Nothing: GitHub merges it. |
| `status: on hold` | A maintainer stopped auto-merge | Wait for the maintainer to remove it. |

```text
opened / pushed ─► needs approval ─(approved)─► waiting for green ─(all green)─► automerge ─► merged
                                                      │
                                                      └─(check fails)─► ci failed ─(fixed)─► waiting for green
```

Only approvals from people with write access count, and never the author's own
(GitHub does not allow self-approval either). Only people with write access can
use `status: on hold`; the bot removes it otherwise. `status:` labels are
managed by the bot: a label set by hand is corrected on the next run.
GitHub itself only lets collaborators with triage access or more apply labels.

Pushing a new commit dismisses earlier approvals (shown as `github-actions[bot]`),
so code nobody reviewed can never auto-merge. Only branch protection decides
whether the merge is allowed; the workflow just turns on auto-merge.

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

## The bot

`.github/workflows/bot.yml` posts short guidance as `github-actions[bot]` and
keeps the `needs:` labels in sync. Comments are static text, posted once, and
never repeat anything from the issue.

| When | What the bot does |
|---|---|
| An issue is opened | Welcomes the reporter, explains the automatic labels and what details to include. |
| A pull request is opened | Posts the checklist: Conventional Commit title, required checks, one approval, version bump and the `status:` lifecycle. |
| `needs: info` is added | Asks the reporter for version, `flutter doctor -v`, platform and a minimal reproduction. |
| The reporter replies on a `needs: info` issue | Removes `needs: info` and adds `needs: triage` so a maintainer looks again. |
| `good first issue` or `help wanted` is added | Invites contributors to comment and links the contributing guide. |

## Triage checklist (maintainers and triagers)

1. Read the issue and remove `needs: triage`.
2. Make sure `p:` and `platform:` are right and add `type: fix` or `type: feat`.
3. Not enough detail? Add `needs: info` and ask for what is missing.
4. Not a bug or already tracked? Add `question`, `duplicate`, `invalid` or
   `wontfix`, comment why, and close.
5. Worth fixing but not by you? Add `help wanted`, plus `good first issue` if it
   is beginner friendly.

## Merging (maintainers)

Approve the PR. When all checks are green GitHub squash-merges it by itself
(`status: automerge`). To stop that, add `status: on hold`; remove it to resume.
Dependabot patch and minor PRs also enable auto-merge on their own
(`dependabot-auto-merge.yml`) but still need an approval.

## Changing labels

Edit `.github/labels.json` (the workflow syncs it on `main`). Path-based rules
live in `.github/labeler.yml`, issue-text rules in `.github/workflows/issue-labeler.yml`,
the `type` / `breaking-change` logic in `.github/workflows/pr-labels.yml`, and the
status lifecycle in `.github/workflows/pr-status.yml`.
