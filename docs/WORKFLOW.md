# Ticket workflow

Every change starts as a **Feature** issue (`.github/ISSUE_TEMPLATE/feature.yml`) describing
one behavior, its acceptance criteria, and what is out of scope. Blank issues are disabled.

Two templates create the same ticket:
- **Feature:** a form with one field per section, with guidance. Good for writing a ticket from scratch.
- **Feature (paste whole ticket)** (`feature_paste.md`): one Markdown box. Paste a complete ticket,
  such as one Claude drafted, in a single go. Keep the `### Behavior`, `### Acceptance criteria`,
  `### Out of scope`, `### Context (optional)` and `### Size check` headings. Both templates apply
  the `feature` label.

GitHub holds the tickets, the history and CI. The AI work runs **locally in Claude Code**,
one command per phase, billed to your Claude subscription. Nothing on GitHub calls an AI.

## Statuses

A ticket's status is a single label. Applying a new status label removes the old one.

```
(no status) → [needs-clarification] → tests-proposed → tests-approved → in-progress → ready-for-review → merged
                    optional                            (owner only)
```

| Label | Applied by | Meaning |
|---|---|---|
| `needs-clarification` | Claude or you | Claude's questions are in a comment. **Waiting on you** to answer. |
| `tests-proposed` | Claude | A draft PR from `ticket-<N>-<slug>` holds failing tests. **Waiting on you** to review. |
| `tests-approved` | **You, by hand** | **The approval gate.** You reviewed the tests and approved them. |
| `in-progress` | Claude | Claude is implementing against the approved tests. |
| `ready-for-review` | Claude | CI is green and the PR is out of draft. **Waiting on you** to review and merge. |

## Running a ticket

| Step | You do | Claude does |
|---|---|---|
| 1 | Open a Feature issue on GitHub, or run `/new-ticket <what you want>` | With `/new-ticket`: drafts the ticket(s) in the Feature format, splits big requests, asks in chat if something is unclear, shows you the text, then files each issue with the `feature` label and tells you its number |
| 2 | `/write-tests <N>` | Checks the ticket is ready (skipped for tickets filed by `/new-ticket`, which were already checked with you, unless you've commented since). If not, posts numbered questions on the issue and applies `needs-clarification`, then stops. If it is, writes failing tests on `ticket-<N>-<slug>`, and drafts the PR and comment for you to post |
| 3 | If Claude asked questions: answer on the issue (or edit the ticket), then run `/write-tests <N>` again | |
| 4 | Commit and push the tests, open the draft PR, apply `tests-proposed` | |
| 5 | Review the PR's tests. Apply `tests-approved`, or comment and re-run `/write-tests <N>` | |
| 6 | `/implement <N>` | Implements, watches CI until green, marks the PR ready, applies `ready-for-review` |
| 7 | Review and merge, or comment and re-run `/implement <N>` | |

The commands are in `.claude/commands/`. Shared rules for every phase are in `CLAUDE.md`.
Edit either to tune how Claude works.

## Guarantees

The prompts tell Claude the rules. These checks enforce them:

| Rule | Enforced by |
|---|---|
| Writing tests changes only `tests/` | `tools/ticket_guard.sh tests-only`, run by `/write-tests` before pushing |
| Approved tests can't be weakened | The **`approved-tests` required check** (`.github/workflows/approved-tests.yml`), also run locally by `/implement` |
| Claude never approves | The `.claude/hooks/block-self-approval.sh` hook blocks any command that would apply `tests-approved` |
| One status at a time, and only you move tickets | `.github/workflows/ticket-status.yml` |

### The approved-tests check

This is the most important guard. Without it, the AI could "pass" by quietly weakening the tests.

1. When you apply `tests-approved`, the **Record test approval** workflow posts a comment from
   `github-actions[bot]` with a hidden marker naming the commits you approved: the current head of every branch for the
   ticket. Neither you nor
   Claude can post as that account, so the marker can't be faked.
2. On every PR update, `approved-tests` finds the tickets the PR implements: from its branch name
   (`ticket-<N>-<slug>`, or legacy `ticket/<N>`), plus any issue it closes. A ticket can have several PRs.
   For each Feature ticket it fails if:
   - the tests were never approved (draft PRs get a pass while waiting for approval)
   - the branch doesn't contain an approved commit (it was rebased, force-pushed, squashed,
     or branched from somewhere other than the approved tests)
   - anything that decides whether the tests pass has changed since approval: `tests/`,
     `addons/gut/`, `.gutconfig.json`, `tools/` or `.github/`. This covers edited, deleted and
     *added* tests, a patched test framework, a narrowed test config, and edited test scripts or CI.
   - Merging `main` into a ticket branch is fine: a protected file that's identical to `main`'s
     version passes, except the ticket's own test files, which must stay exactly as approved.
3. It runs on `pull_request_target`, so GitHub always uses the version on `main`. A PR can't
   edit or delete it. It never runs code from the PR, only `git diff` with the guard script from `main`.

If an approved test really is wrong, `/implement` stops and asks instead. You fix it through
`/write-tests` and approve again, which records a new approved commit.

**Several PRs per ticket:** name every branch `ticket-<N>-<slug>` (e.g. `ticket-1-player-movement`,
`ticket-1-fix-diagonal-speed`) and branch it from the approved tests, or from `main` once the tests
are merged. Merge ticket PRs with a **merge commit**, not squash or rebase: those create new
commits, so the approved commit wouldn't be in `main`'s history, and later PRs for the ticket would fail.

**Limit:** a PR whose branch isn't named `ticket-<N>-…` and that closes no Feature issue isn't
checked, because there are no approved tests to compare against. The check catches mistakes, but you still read what you merge.

**What GitHub can't see:** Claude uses your `gh` login, so on GitHub its comments and labels are
indistinguishable from yours. The local hook stops it from approving. The CI check makes sure that,
even so, nothing merges with changed tests unless you notice.

## Who can run tickets

Only the **repository owner** can move tickets. The repo is public, so anyone can open issues and
comment. `ticket-status.yml` removes any status label applied by anyone else, including collaborators
and bots, and comments explaining why. The commands also refuse tickets not written by you, and
treat only your comments as instructions.

## Setup

**Once per machine:**
1. Install the GitHub CLI (https://cli.github.com), then run `gh auth login`.
2. Point `GODOT` at your Godot console executable in `.claude/settings.local.json`
   (gitignored, since the path differs per machine).

**Once per repository** (Settings on GitHub):
1. Branches: protect `main`.
   - Require a pull request before merging.
   - Require the `godot-checks` and `approved-tests` status checks. `approved-tests` only appears in the list after it has run once, so open a PR first.
2. Actions → General → *Fork pull request workflows from outside collaborators*: set to
   **Require approval for all external contributors**.
3. Don't give anyone else Triage or Write access.

## Labels

Labels are defined in `.github/labels.json`. The `Sync labels` workflow creates or updates them
whenever that file changes on `main`. You can also run it by hand from the Actions tab.
The `agents` list there is empty: no bot account is allowed to move tickets.
