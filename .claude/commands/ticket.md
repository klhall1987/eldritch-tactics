---
description: Take a Feature ticket end to end in one go - check it, write failing tests, implement, verify - and hand over one diff for a single review
argument-hint: <issue-number>
---

Take ticket #$ARGUMENTS from ticket to finished implementation **in one run**: check it's ready, write
failing tests, implement until they pass, and hand me one diff to review. Follow the ticket rules in
CLAUDE.md. This replaces running `/write-tests` and then `/implement`, with one review instead of two.

I review the tests once, at the end, together with the code. So the tests have to earn trust on their
own. Write them from the ticket **before** any implementation, prove they fail for the right reasons,
and then **freeze** them.

## 1. Read and check the ticket

Do steps 1 and 2 of `.claude/commands/write-tests.md` exactly as written: read the ticket and its
comments, check it's the owner's Feature ticket, check queue dependencies (asking me if one is still
open), and check it's ready (skipped for tickets filed by `/new-ticket`, unless I've commented since).

If anything needs clarifying, do what step 2 says (post numbered questions, apply
`needs-clarification`) and stop. Say `/ticket $ARGUMENTS` is what to run again.

## 2. Branch

- `git fetch origin`. Make sure the working tree is clean. If it isn't, stop and tell me what's
  uncommitted, rather than carrying it onto the ticket branch.
- If `origin/ticket-$ARGUMENTS-*` branches already exist, this ticket is already part-way through the
  two-step flow: stop, and tell me to carry on with `/write-tests` or `/implement` instead.
- Otherwise: `git switch --no-track -c ticket-$ARGUMENTS-<slug> origin/main`, with a slug of a few words
  from the title in lowercase-kebab-case.

## 3. Write the failing tests (tests phase)

Follow step 4 of `.claude/commands/write-tests.md`: tests in `tests/unit/test_<feature>.gd`, at least
one per acceptance criterion with its text in a comment above it, `load()` rather than `preload`,
interface choices kept small and consistent with the existing code, and every test checking
something even when the feature is missing. **Only files under `tests/` change in this phase.**

Then verify, as step 5 there says, running **only the test files you added or changed**
(`bash tools/run_tests.sh tests/unit/test_<feature>.gd ...`). The full suite runs once, in step 5:
- every new test fails for the right
  reason (a missing script, node, function or behavior). Typos and parse errors don't count. A new
  test that already passes is only fine if its criterion is already true before the work (say so).
- `git status --porcelain` lists only paths under `tests/`.
- Note each new test's failure message. They go in the PR as evidence the tests test something.

**Freeze the tests.** Record their fingerprint:

```bash
find tests -type f -name '*.gd' | sort | xargs sha1sum | sha1sum
```

## 4. Implement (implementation phase)

Follow step 2 of `.claude/commands/implement.md`: the smallest implementation that makes the tests
pass, code in `scripts/`, `scenes/` (and `assets/` or `art/` only if the ticket needs it), nothing
from Out of scope.

- **Don't touch `tests/`** from here on, and never `addons/gut/`, `.gutconfig.json`, `tools/` or
  `.github/`. If a frozen test turns out to be wrong (it contradicts another test or the ticket, or
  can't pass without something out of scope), **stop**. Explain on the issue, propose the test
  change, apply `needs-clarification`, and tell me. Never weaken a test to fit the code.
- While implementing, run just the ticket's test files (`bash tools/run_tests.sh <files>`), plus the
  files of any existing tests your change could affect. Save the full suite for step 5.
- Look at the result, not just the tests. For art, check the previews or render the model. For
  scenes, capture a frame of the running game. Fix what the tests can't see.

## 5. Verify everything

- `bash tools/run_tests.sh` (the full suite, once): every test passes. Run it a second time only if
  a new test depends on timing or randomness that the seeds don't fix.
- `bash tools/smoke_test.sh`: passes.
- Run the fingerprint command again. It must match the one from step 3, proving the tests are
  exactly as written before implementing. If it doesn't, find out why and stop.
- `git status --porcelain`: nothing under `addons/gut/`, `.gutconfig.json`, `tools/` or `.github/`.

## 6. Hand off (don't commit or push)

1. Leave everything **uncommitted** on the ticket branch: tests and implementation together.
2. Write the PR body to `.agent/pr.md`:
   - `Closes #$ARGUMENTS`
   - what changed and why
   - the criteria-to-tests table
   - the interface and measurement choices the tests make (accepting the PR accepts them)
   - **evidence:** each new test's failure message before implementing, that all tests pass after, and
     the matching test fingerprints
3. Write a one-paragraph issue comment to `.agent/comment.md`.
4. Apply `in-progress`: `bash tools/github.sh label $ARGUMENTS in-progress`.
5. Tell me it's ready for review: what was built, the choices the tests made, anything I should look
   at closely, and screenshots or previews if it's visible. Then list my next steps:
   - review the diff (tests and code), then commit and push the branch (one commit is fine)
   - open the PR with `.agent/pr.md`
   - post `.agent/comment.md`, and apply `ready-for-review` once CI is green
6. If CI fails after I push, I'll run `/implement $ARGUMENTS`, which picks up from there.
