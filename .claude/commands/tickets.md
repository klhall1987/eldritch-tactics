---
description: Work several Feature tickets in order, each the /ticket way, committing, pushing and opening one stacked PR per ticket
argument-hint: <issue-number> <issue-number> ...
---

Work tickets **$ARGUMENTS** one after another, **in exactly the order listed**. Each ticket goes
through the `/ticket` flow (check, failing tests, freeze, implement, verify). Then, unlike `/ticket`,
you commit it, push it and open its PR yourself, and branch the next ticket off this one. Follow the
ticket rules in CLAUDE.md.

**Committing and pushing are allowed in this command only**, and only like this:
- commit only on the current ticket's own `ticket-<N>-<slug>` branch
- push only that branch, by name: `git push -u origin ticket-<N>-<slug>`
- never push to `main`, never force-push, never rebase or amend a pushed commit, never merge a PR
- open PRs with `gh pr create`; never mark one for auto-merge

## 0. Before starting

1. Parse the issue numbers from `$ARGUMENTS` (spaces or commas). If there are none, stop and ask.
2. `git fetch origin`. The working tree must be clean. If it isn't, stop and tell me what's
   uncommitted, rather than carrying it onto a ticket branch.
3. **Check every ticket up front**, so questions come before any work. For each one, do steps 1 and 2
   of `.claude/commands/write-tests.md` (read it and its comments, check it's the owner's Feature
   ticket, check it's ready, skipped for tickets filed by `/new-ticket` unless I've commented since),
   with one change to the dependency check:
   - a dependency that appears **earlier in this list** is fine, since it will be underneath in the stack
   - a dependency that is **later in this list** means the order is wrong: stop and tell me
   - any other dependency that's still open: stop and ask me in chat whether to go ahead
4. If any `origin/ticket-<N>-*` branch already exists for a listed ticket, stop and tell me which:
   it's already part-way through another flow.
5. If any ticket needs clarifying, post its questions and apply `needs-clarification` as step 2 of
   `write-tests.md` says. Then work only the tickets **before** the first unclear one (none, if it's
   the first), and say so before starting.

## 1. For each ticket, in order

Call the previous ticket's branch `<base>`: `origin/main` for the first ticket, the branch you just
pushed for every later one.

1. **Branch:** `git switch --no-track -c ticket-<N>-<slug> <base>`, with a slug of a few words from the
   title in lowercase-kebab-case. Apply `in-progress`: `bash tools/github.sh label <N> in-progress`.
2. **Tests, freeze, implement, verify:** steps 3, 4 and 5 of `.claude/commands/ticket.md`, exactly as
   written: failing tests first (only `tests/` changes, each fails for the right reason, failure
   messages noted), the fingerprint, the smallest implementation, a look at the result, then all tests
   and the smoke test pass and the fingerprint still matches. The earlier tickets' tests are part of
   the suite and must keep passing.
3. **Commit:** check `git status --porcelain` shows only this ticket's files, and nothing under
   `addons/gut/`, `.gutconfig.json`, `tools/`, `.github/` or `.agent/`. Commit with the message
   `<ticket title without [Feature]> (#<N>)`. Commit the tests first and the implementation second if
   that's easy (two commits, so the failing-tests commit is visible); one commit is fine too.
   Then `bash tools/ticket_guard.sh protected <base> HEAD` must print OK.
4. **Push:** `git push -u origin ticket-<N>-<slug>`.
5. **PR:** write the body to `.agent/pr-<N>.md` as step 6 of `ticket.md` describes (`Closes #<N>`, what
   changed, the criteria-to-tests table, the interface choices, the failing-then-passing evidence and
   fingerprints). For every ticket after the first, add a line at the top:
   `Stacked on #<previous PR number> (#<previous ticket>). Merge that first.`
   Then open it:
   `gh pr create --base <base branch name, main for the first> --head ticket-<N>-<slug> --title "<ticket title>" --body-file .agent/pr-<N>.md`
6. **Report on the issue:** write a one-paragraph comment with the PR link to `.agent/comment-<N>.md`,
   post it with `bash tools/github.sh comment <N> .agent/comment-<N>.md`, and apply
   `bash tools/github.sh label <N> ready-for-review`. If posting fails, note it for the hand-off and
   carry on.
7. Move on to the next ticket, with this ticket's branch as `<base>`.

## 2. When to stop early

Stop the whole run, leaving later tickets untouched, if a ticket:
- turns out to need clarification mid-way (a frozen test is wrong, or can't pass without something
  out of scope): do what step 4 of `ticket.md` says (explain on the issue, apply `needs-clarification`),
  leave that ticket's work **uncommitted** on its branch, and don't push it
- can't be made to pass, or the fingerprint doesn't match: leave it uncommitted and tell me why
- fails to push or to open its PR: stop and tell me the error; don't retry with force

Tickets already pushed stay as they are.

## 3. Hand off

Tell me:
- the stack, bottom to top, as a checklist: each ticket's number and title, its branch, its PR link and
  its base, and what was built (with screenshots or previews if it's visible)
- the choices the tests made that I should look at, per ticket
- where and why the run stopped, if it stopped early, and which tickets weren't started
- anything you couldn't post on GitHub, with the `.agent/` file to post by hand
- how to merge: bottom PR first, with a merge commit (not squash), then each one up the stack as
  GitHub retargets it at `main`. If I ask for changes in a lower PR, `/implement <N>` fixes it on that
  branch, and the PRs above need that branch merged into them.
