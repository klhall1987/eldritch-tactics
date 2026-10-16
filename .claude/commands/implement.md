---
description: Implement a ticket against its tests until they and CI pass, then hand over for review
argument-hint: <issue-number>
---

Implement ticket #$ARGUMENTS against its tests (written by `/write-tests` and reviewed by me).
Follow the ticket rules in CLAUDE.md.

## 1. Find the tests

- Read the ticket: `gh issue view $ARGUMENTS --json title,body,labels,author,comments`.
- Find the ticket's branches: `git fetch origin && git branch -r --list "origin/ticket-$ARGUMENTS-*" "origin/ticket/$ARGUMENTS"`.
  Read each one's PR and the owner's feedback on it: `gh pr view <branch> --comments`.
- If no branch holds pushed tests for this ticket, **stop**: run `/write-tests $ARGUMENTS` first.
- If the issue is labelled `ready-for-review`, this run addresses the owner's feedback since the
  last push.

## 2. Implement

- Work on the tests branch: `git switch <branch> && git pull --ff-only`.
  For extra work in a separate PR (for example a follow-up fix), branch from it:
  `git switch --no-track -c ticket-$ARGUMENTS-<slug> <tests-branch>`.
- **Don't change the tests, or anything that decides whether they pass.** Don't modify,
  delete, rename or add anything in `tests/`, `addons/gut/`, `.gutconfig.json`, `tools/` or
  `.github/`.
- Never rebase or rewrite the branch.
- Write the smallest implementation that makes the tests pass. Code goes in `scripts/`, `scenes/`
  (and `assets/` or `art/` only if the ticket needs it). Nothing from Out of scope.
- If the tests can't pass without changing them, stop. That covers a test that's wrong,
  contradicts another test, or depends on something out of scope. Comment on the issue explaining
  the problem and proposing the test change, apply `needs-clarification`, and tell me.

## 3. Verify locally

- While fixing, run just the relevant test files (`bash tools/run_tests.sh tests/unit/test_<feature>.gd ...`).
- Then `bash tools/run_tests.sh` (the full suite, once): every test passes.
- `bash tools/smoke_test.sh`: passes.
- `git status --porcelain` must list nothing under `tests/`, `addons/gut/`, `.gutconfig.json`,
  `tools/` or `.github/`.

## 4. Hand off (don't commit or push)

1. Leave the implementation **uncommitted** on the ticket branch. I review the diff, then
   commit and push it myself.
2. Write an updated PR description to `.agent/pr.md` (keep `Closes #$ARGUMENTS`) and an issue
   comment to `.agent/comment.md` with a one-paragraph summary.
3. Apply `in-progress`: `bash tools/github.sh label $ARGUMENTS in-progress` (skip if it already is).
4. Tell me it's ready for review, and list my next steps:
   - review the diff, then commit and push
   - update the PR with `.agent/pr.md`, mark it ready, and post `.agent/comment.md`
   - apply `ready-for-review` once CI is green
5. If CI fails after I push, I'll run `/implement $ARGUMENTS` again. Read the failed check
   (`gh run view <run-id> --log-failed`, or ask me for the log) and fix it, still without committing.
