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
(no status) → [needs-clarification] → in-progress → ready-for-review → merged
                    optional
```

| Label | Applied by | Meaning |
|---|---|---|
| `needs-clarification` | Claude or you | Claude's questions are in a comment. **Waiting on you** to answer. |
| `in-progress` | Claude | Tests and implementation are underway on `ticket-<N>-<slug>`. |
| `ready-for-review` | Claude or you | The PR is open and CI is green. **Waiting on you** to review and merge. |

## Filing tickets: `/new-ticket <what you want>`

Splits big requests into a queue of small tickets in build order, each naming the ticket it depends
on. Drafts them in the Feature format and shows you the queue, the full text and the decisions it
made (each one you can change), then asks **Does all this look good?** Anything but yes is treated
as feedback: it revises and asks again. On yes, it files each issue in order with the `feature` label
and lists the queue with issue numbers.

## Working tickets

There are three ways to work a ticket, from most to least hands-on.

### A feature: `/feature <N> <N> ...`

Works several **related** tickets (usually one `/new-ticket` queue) as one feature, in the order
given, and this time Claude commits, pushes and opens the PR itself: **one PR for all of them**, on
one branch, `feature-<slug>`, with a commit per ticket.

To spend less time waiting on tests, the work goes in batches rather than ticket by ticket:

1. **Tests:** Claude writes the failing tests for every ticket, runs them all once to check each fails
   for the right reason, freezes them (a fingerprint of `tests/`) and commits them, one commit per
   ticket.
2. **Implementations:** it builds every ticket in order without running the suite in between. It only
   runs a ticket's own tests early when the work needs a result, such as a model it has just built.
3. **Verify:** it runs the feature's tests together, fixes until they pass, then runs the full suite
   and the smoke test once, and checks the fingerprint still matches.

The PR has one `Closes #<N>` line per ticket, so merging it closes them all, plus each ticket's
criteria-to-tests table, its tests' choices and its failing-then-passing evidence. Merge it into
`main` with a merge commit to keep the per-ticket commits.

Claude stops if a ticket needs clarification, or can't be made to pass. Nothing is pushed until the
whole feature passes, so a stopped run leaves only the local `feature-<slug>` branch, with the tests
committed and the implementation uncommitted. Answer on the issue and run the same `/feature`
command again to carry on from there.

This is the only command that commits or pushes. It never pushes to `main`, never force-pushes and
never merges.

### One ticket: `/ticket <N>`

| Step | You do | Claude does |
|---|---|---|
| 1 | `/ticket <N>` | Checks the ticket is ready (asking on the issue if not, like `/write-tests`). Then, on a new `ticket-<N>-<slug>` branch: writes the failing tests from the ticket, checks each fails for the right reason, **freezes** them (records a fingerprint of `tests/`), implements, checks everything passes and the fingerprint still matches, and drafts the PR and comment, with the failing-then-passing evidence |
| 2 | Review the one diff (tests and code). Commit and push, open the PR, post the comment, and apply `ready-for-review` once CI is green | |
| 3 | If CI fails, run `/implement <N>` | Fixes it |

### Phase by phase: `/write-tests <N>`, then `/implement <N>`

| Step | You do | Claude does |
|---|---|---|
| 1 | `/write-tests <N>` | Checks the ticket is ready (skipped for tickets filed by `/new-ticket`, unless you've commented since). If not, posts numbered questions on the issue and applies `needs-clarification`, then stops. If it is, writes failing tests on `ticket-<N>-<slug>`, and drafts the PR and comment for you to post |
| 2 | If Claude asked questions: answer on the issue (or edit the ticket), then run `/write-tests <N>` again | |
| 3 | Review the tests. Commit and push them and open a draft PR, or comment and re-run `/write-tests <N>` | |
| 4 | `/implement <N>` | Implements against the pushed tests, without changing them |
| 5 | Review, commit and push, mark the PR ready, apply `ready-for-review` once CI is green. Merge, or comment and re-run `/implement <N>` | |

If `/new-ticket` made a queue, work it top to bottom. `/write-tests` and `/ticket` check that a
ticket's dependency is merged first, and ask you if it isn't. `/feature` doesn't need to: it builds
each ticket on the ones before, on the same branch.

The commands are in `.claude/commands/`. Shared rules for every phase are in `CLAUDE.md`.
Edit either to tune how Claude works.

## Guarantees

There is no separate approval step: you review the tests and the code together in the PR, and
merging is the approval. These keep the tests honest:

| Rule | Enforced by |
|---|---|
| Tests are written before the code, and fail first | `/ticket` and `/feature` record each new test's failure message in the PR |
| Tests aren't changed to fit the code | `/ticket` and `/feature` fingerprint `tests/` after writing them and check it still matches after implementing; `/implement` never touches `tests/` |
| A ticket never changes the test harness | `tools/ticket_guard.sh protected` (`addons/gut/`, `.gutconfig.json`, `tools/`, `.github/`) |
| Writing tests changes only `tests/` | `tools/ticket_guard.sh tests-only` |
| Every PR passes the tests and the smoke run | The required `godot-checks` check (`.github/workflows/ci.yml`) |
| One status at a time, and only you move tickets | `.github/workflows/ticket-status.yml` |

These are checks Claude runs on itself, not CI gates: still read what you merge, especially any
change under `tests/`.

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
   - Require the `godot-checks` status check.
2. Actions → General → *Fork pull request workflows from outside collaborators*: set to
   **Require approval for all external contributors**.
3. Don't give anyone else Triage or Write access.

## Labels

Labels are defined in `.github/labels.json`. The `Sync labels` workflow creates or updates them
whenever that file changes on `main`. You can also run it by hand from the Actions tab.
The `agents` list there is empty: no bot account is allowed to move tickets.
