---
description: Turn a description of what you want into Feature tickets, check them, and file them on GitHub
argument-hint: <what you want, in your own words>
---

Write Feature tickets for this request and file them on GitHub:

$ARGUMENTS

Follow the ticket rules in CLAUDE.md. **Don't write code or tests** in this command.

## 1. Understand the request

- Read the code the request touches (scenes, scripts, the asset library, existing tests), so the
  ticket names real nodes, scripts and assets and fits what's already built.
- Check the open issues for overlap: `bash tools/github.sh issue <N>` for any you already know
  of from this conversation. If the request duplicates or contradicts an open ticket, say so.

## 2. Split into a queue

Before drafting, decide whether this is one ticket or several. Split it when any of these hold:
- it describes more than one behavior ("and", "then", "also", several triggers or results)
- it needs more than 5 acceptance criteria to cover
- part of it needs something that doesn't exist yet (a camera, a scene, an asset, a script),
  and that something is worth testing on its own
- parts could be reviewed or merged independently

If it splits, plan a **queue**: the tickets in build order, each one small, testable, and
built only on the ones before it. Each later ticket lists what it depends on (see Context
below). Don't ask whether to split; just do it and show me the queue in step 4. If one
ticket is enough, say so in one line.

## 3. Draft

Write each ticket in the Feature template's format, with exactly these headings:

```markdown
### Behavior

When <trigger>, <observable result>.

### Acceptance criteria

- [ ] Given ..., when ..., then ...

### Out of scope

- ...

### Context (optional)

- ...

### Size check

- [x] This describes one behavior, not several.
- [x] Every acceptance criterion can be checked by a unit test, without anyone playing.
```

- Title: `[Feature] <short description>`.
- **One behavior per ticket, 1-5 acceptance criteria**, each checkable by a unit test without
  anyone playing.
- **Out of scope** lists what's deliberately left for later, so the ticket stays small.
- **Context** points at the existing code to build on and any traps (node names earlier tests
  rely on, protected files, assets to use), like the tickets already in the repo.
- In a queue, every ticket's Context starts with a line like
  `- Queue: part 2 of 3 for "<short request>". Depends on #<N> (<its title>).`
  Part 1 says `Depends on nothing.` (or on an existing open ticket, if it does). Write the
  dependency as `#DEP-<k>` (k = its part number) in the draft; step 5 swaps in the real number.
  Out of scope in earlier tickets should point at the later ones ("the cultist in the world:
  part 2").

## 4. Check before showing

Run the same checks as `/write-tests`:
- one behavior; 1-5 unambiguous, unit-testable criteria
- nothing contradicts the Out of scope list or the Behavior
- interface details (node names, functions, measurements) are left for `/write-tests` to
  choose, unless they change what the feature does
- in a queue: the order works (no ticket needs a later one), and nothing is covered twice or
  falls between two tickets

If something would change what the feature does and the request doesn't say (e.g. a number,
which side of the screen, what happens in an edge case), pick the most sensible answer, write
it into the ticket, and list it under **Decisions I made** in step 5 so I can change it. Don't
ask separate questions or offer "defaults": the drafts I see are exactly what gets filed.

## 5. Show, ask, then file

1. Write each ticket body to `.agent/ticket-<slug>.md`, ending with the line
   `<!-- checked: /new-ticket -->`. It's invisible on GitHub, and tells `/write-tests` the
   ticket already passed these checks with my agreement, so it can skip re-checking.
2. Show me:
   - the queue, if there's more than one ticket: a numbered list of titles in build order,
     each with what it depends on
   - each ticket's title and full text
   - **Decisions I made**: a short numbered list of the choices I might want to change, each
     saying what you picked and the main alternative (e.g. "1. Walk animates in place, not
     with root motion")
3. End with exactly this question: **Does all this look good?** Then stop and wait.
4. Read my reply:
   - **Yes** (or "looks good", "file them", and so on): file the tickets exactly as shown.
   - **Anything else** is feedback: change any decision, add, merge, split or drop tickets
     as I ask, rerun the checks in step 4, rewrite the `.agent/` files, show what changed (the
     full text of any changed ticket, and the queue if it changed), and ask
     **Does all this look good?** again. Repeat until I say yes. Never file before that.
5. File them one at a time, in build order:
   `bash tools/github.sh create "<title>" .agent/ticket-<slug>.md`
   (this asks for my permission; it adds only the `feature` label). After each one, replace
   `#DEP-<k>` in the remaining `.agent/ticket-*.md` files with the number just created, so
   every ticket links to its real dependency.
6. If filing fails (e.g. the token can't write issues), stop filing and tell me which were filed.
   Tell me to paste the rest of the `.agent/ticket-<slug>.md` files into **Feature (paste whole
   ticket)** on GitHub instead, in order, replacing each `#DEP-<k>` with the real number.
7. Finish with the queue as a checklist with the real numbers and links, e.g.

   ```
   1. [ ] #5 [Feature] Isometric camera and ground (https://...)  → /write-tests 5 is next
   2. [ ] #6 [Feature] Cultist stands in the world, depends on #5
   ```

   Work through it top to bottom: each ticket goes through `/write-tests` and `/implement`
   before the next. Say that `/write-tests <first N>` is next.
