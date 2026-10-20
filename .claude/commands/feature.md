---
description: Work several related Feature tickets as one feature - all their tests first, then all their implementations, then one test run - and open a single PR for the lot
argument-hint: <issue-number> <issue-number> ...
---

Work tickets **$ARGUMENTS** as **one feature**, in the order listed. They're related tickets (usually a
`/new-ticket` queue), so they're built together and handed over as **one PR**. To save time waiting on
tests, the work goes in batches, not ticket by ticket:

1. **Tests:** write the failing tests for *every* ticket, then run them all once.
2. **Implementations:** build *every* ticket's implementation, in order, without running the suite in
   between.
3. **Verify:** run the feature's tests, fix until they pass, then run the full suite and the smoke
   test once.

Follow the ticket rules in CLAUDE.md. Each ticket keeps the `/ticket` guarantees: its tests are written
from the ticket before any implementation, fail for the right reason first, and are frozen.

**Committing and pushing are allowed in this command only**, and only like this:
- commit only on this feature's own `feature-<slug>` branch
- push only that branch, by name: `git push -u origin feature-<slug>`
- never push to `main`, never force-push, never rebase or amend a pushed commit, never merge a PR
- open the PR with `gh pr create`; never mark it for auto-merge

## 0. Before starting

1. Parse the issue numbers from `$ARGUMENTS` (spaces or commas). If there are none, stop and ask.
2. `git fetch origin`. The working tree must be clean. If it isn't, stop and tell me what's
   uncommitted, rather than carrying it onto the feature branch. (Resuming a stopped run is the
   exception: see section 6.)
3. **Check every ticket up front**, so questions come before any work. For each one, do steps 1 and 2
   of `.claude/commands/write-tests.md` (read it and its comments, check it's the owner's Feature
   ticket, check it's ready, skipped for tickets filed by `/new-ticket` unless I've commented since),
   with one change to the dependency check:
   - a dependency that appears **earlier in this list** is fine: it's built first, on the same branch
   - a dependency that is **later in this list** means the order is wrong: stop and tell me
   - any other dependency that's still open: stop and ask me in chat whether to go ahead
4. **Name the feature:** a few words in lowercase-kebab-case for the branch, `feature-<slug>`, and a
   short title for the PR. Take them from the tickets' shared `Queue: ... for "<request>"` line if
   they have one, otherwise from what the tickets have in common. If `origin/feature-<slug>` or any
   `origin/ticket-<N>-*` branch already exists for a listed ticket, stop and tell me: it's already
   part-way through another flow.
5. If any ticket needs clarifying, post its questions and apply `needs-clarification` as step 2 of
   `write-tests.md` says. Then work only the tickets **before** the first unclear one (none, if it's
   the first), and say so before starting.

## 1. Branch

`git switch --no-track -c feature-<slug> origin/main`. Apply `in-progress` to every ticket being
worked: `bash tools/github.sh label <N> in-progress`.

## 2. Phase A: every ticket's tests

1. **Write the tests for each ticket, in order**, as step 4 of `.claude/commands/write-tests.md` says:
   files under `tests/` only, at least one test per acceptance criterion with its text in a comment,
   `load()` rather than `preload` for code that doesn't exist yet, interface choices kept small and
   consistent with the existing code and with **the earlier tickets' tests** (a later ticket's tests
   build on the interface the earlier ones chose). Don't run anything between tickets.
2. **Run all the feature's new and changed test files once, together**:
   `bash tools/run_tests.sh <every test file this feature added or changed>`. Every new test must fail
   for the right reason: a missing script, node, function, asset or behavior. That includes one that
   fails only because an earlier ticket in this feature isn't built yet. Typos and parse errors don't
   count: fix them and re-run **just those files**. A new test that already passes is only fine if its
   criterion is already true before the work (say so). Note each new test's failure message.
3. `git status --porcelain` lists only paths under `tests/`.
4. **Freeze the tests.** Record their fingerprint:
   ```bash
   find tests -type f -name '*.gd' | sort | xargs sha1sum | sha1sum
   ```
   If a ticket deletes test files, the fingerprint covers every test except those, and must match
   again after they're deleted.
5. **Commit the tests, one commit per ticket**, each `Tests: <ticket title without [Feature]> (#<N>)`,
   staging that ticket's test files. If several tickets change the same test file, commit it once,
   naming every ticket it serves (`Tests: <feature title> (#<N>, #<N>)`).

## 3. Phase B: every ticket's implementation

1. **Implement each ticket, in order**, as step 2 of `.claude/commands/implement.md` says: the smallest
   implementation that makes its tests pass, code in `scripts/`, `scenes/` (and `assets/` or `art/` only
   if the ticket needs it), nothing from Out of scope, never touching `tests/`, `addons/gut/`,
   `.gutconfig.json`, `tools/` or `.github/`. Each ticket builds on the ones before it.
2. **Don't run the test suite between tickets.** Run something before Phase C only when a ticket
   can't be built without seeing a result. Examples: a Blender script that makes the asset the tests
   measure, a reimport, or tuning numbers against a measurement. Then run **only that ticket's test
   files**, and only as often as the work needs.
3. **Look at the result, not just the tests.** For art, check the previews or render the model. For
   scenes, capture a frame of the running game. Fix what the tests can't see.

## 4. Phase C: verify

1. Run **all the feature's test files together**. Fix failing tickets (implementation only) and re-run
   just the files that failed, until all pass.
2. Then once: `bash tools/run_tests.sh` (the full suite) and `bash tools/smoke_test.sh`. Every test
   passes, including the tests from before this feature. If something fails, fix it and re-run the
   full suite once more. Run it a second time only if a new test depends on timing or randomness the
   seeds don't fix.
3. Run the fingerprint command again. It must match Phase A's (or the refrozen one, see section 6).
4. **If a frozen test turns out to be wrong** (it contradicts another test or its ticket, or can't pass
   without something out of scope): stop. Explain on that ticket's issue, propose the test change,
   apply `needs-clarification`, and tell me. Leave the implementation **uncommitted** and push nothing.
   Never weaken a test to fit the code.

## 5. Commit, push, one PR

1. `git status --porcelain` shows only this feature's files, and nothing under `addons/gut/`,
   `.gutconfig.json`, `tools/`, `.github/` or `.agent/`.
2. **Commit the implementation, one commit per ticket where the files allow it**, each
   `<ticket title without [Feature]> (#<N>)`. Where tickets share files, combine them in one commit
   naming every ticket. Then `bash tools/ticket_guard.sh protected origin/main HEAD` must print OK.
3. **Push:** `git push -u origin feature-<slug>`.
4. **PR:** write the body to `.agent/pr-feature-<slug>.md`:
   - one `Closes #<N>` line per ticket, at the top, so merging closes them all
   - what the feature does, in a few lines
   - **per ticket**: what changed, the criteria-to-tests table, the interface and measurement choices
     its tests make (accepting the PR accepts them), and its tests' failure messages before
     implementing
   - for the feature: the full suite and smoke test passing, the fingerprints (Phase A's, and any
     agreed refreeze), and anything I should look at closely, with previews or frames if it's visible

   Then open it:
   `gh pr create --base main --head feature-<slug> --title "[Feature] <feature title>" --body-file .agent/pr-feature-<slug>.md`
5. **Report on every issue:** write a one-paragraph comment with the PR link to
   `.agent/comment-<N>.md`, post it with `bash tools/github.sh comment <N> .agent/comment-<N>.md`, and
   apply `bash tools/github.sh label <N> ready-for-review`. If posting fails, note it for the hand-off
   and carry on.

## 6. Stopping and resuming

Stop the whole run if:
- a ticket needs clarification mid-way: section 4 step 4
- it can't be made to pass, or the fingerprint doesn't match: leave it uncommitted and tell me why
- pushing or opening the PR fails: tell me the error; don't retry with force

Nothing is pushed until everything passes, so a stopped run leaves only the local `feature-<slug>`
branch: the tests are committed there, and the implementation is uncommitted.

**Resuming:** when I've answered and run `/feature` again with the same tickets, carry on from that
branch with its uncommitted work, rather than starting over. If I agreed a test change, make exactly
that change, commit it as `Tests: <what changed> (#<N>, agreed on the issue)`, record the new
fingerprint, and post my answer on the issue if I gave it in chat. Then pick up at the phase that
stopped.

## 7. Hand off

Tell me:
- the PR link, its branch, and the tickets it closes, each with its title and what was built (with
  previews or frames if it's visible)
- the choices the tests made that I should look at, per ticket
- where and why the run stopped, if it did, and which tickets weren't worked
- anything you couldn't post on GitHub, with the `.agent/` file to post by hand
- how to merge: one PR, merged into `main` (a merge commit keeps the per-ticket commits). If I ask
  for changes, fix them on `feature-<slug>` (`/implement <N>` for the ticket concerned) and push again.
