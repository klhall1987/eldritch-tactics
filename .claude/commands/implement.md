---
description: Implement an approved ticket until its tests and CI pass, then mark the PR ready
argument-hint: <issue-number>
---

Implement ticket #$ARGUMENTS against its **approved** tests. Follow the ticket rules in CLAUDE.md.

## 1. Check approval

- Read the ticket: `gh issue view $ARGUMENTS --json title,body,labels,author,comments`.
- Find the ticket's branches: `git fetch origin && git branch -r --list "origin/ticket-$ARGUMENTS-*" "origin/ticket/$ARGUMENTS"`.
  Read each one's PR and the owner's feedback on it: `gh pr view <branch> --comments`.
- `bash tools/ticket_guard.sh approved-sha $ARGUMENTS` prints the commits the owner approved.
  The Record test approval workflow posts it when `tests-approved` is applied.
  If it prints nothing, **stop**: the tests aren't approved.
- The issue must be labelled `tests-approved`, `in-progress` or `ready-for-review`. If it's
  `ready-for-review`, this run addresses the owner's feedback since the last push.

## 2. Implement

- Work on the approved tests branch: `git switch <branch> && git pull --ff-only`.
  For extra work in a separate PR (for example a follow-up fix), branch from it:
  `git switch --no-track -c ticket-$ARGUMENTS-<slug> <approved-branch>`. Every PR for the ticket must contain
  an approved commit, so never branch a ticket PR from plain `main` before the tests are merged.
- **Don't change the approved tests, or anything that decides whether they pass.** Don't modify,
  delete, rename or add anything in `tests/`, `addons/gut/`, `.gutconfig.json`, `tools/` or
  `.github/`. The required `approved-tests` check fails the PR if you do.
- Never rebase or rewrite the branch. The approved commit must stay in its history.
- Write the smallest implementation that makes the tests pass. Code goes in `scripts/`, `scenes/`
  (and `assets/` only if the ticket needs it). Nothing from Out of scope.
- If the approved tests can't pass without changing them, stop. That covers a test that's wrong,
  contradicts another test, or depends on something out of scope. Comment on the issue explaining
  the problem and proposing the test change, apply `needs-clarification`, and tell me.

## 3. Verify locally

- `bash tools/run_tests.sh`: every test passes.
- `bash tools/smoke_test.sh`: passes.
- `bash tools/ticket_guard.sh protected "$(bash tools/ticket_guard.sh approved-sha $ARGUMENTS)" HEAD origin/main`: prints OK.
- `git status --porcelain` must list nothing under `tests/`, `addons/gut/`, `.gutconfig.json`,
  `tools/` or `.github/`.

## 4. Hand off (don't commit or push)

1. Leave the implementation **uncommitted** on the ticket branch. I review the diff, then
   commit and push it myself.
2. Write an updated PR description to `.agent/pr.md` (keep `Closes #$ARGUMENTS`) and an issue
   comment to `.agent/comment.md` with a one-paragraph summary.
3. Tell me it's ready for review, and list my next steps:
   - review the diff, then commit and push
   - apply `in-progress`, then `ready-for-review`, once CI is green
   - update the PR with `.agent/pr.md`, post `.agent/comment.md`, and mark the PR ready
4. If CI fails after I push, I'll run `/implement $ARGUMENTS` again. Read the failed check
   (`gh run view <run-id> --log-failed`, or ask me for the log) and fix it, still without committing.
