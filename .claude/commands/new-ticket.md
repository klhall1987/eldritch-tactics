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

## 2. Draft

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
  anyone playing. If the request is bigger, split it into several tickets in build order, and
  say which depends on which.
- **Out of scope** lists what's deliberately left for later, so the ticket stays small.
- **Context** points at the existing code to build on and any traps (node names earlier tests
  rely on, protected files, assets to use), like the tickets already in the repo.

## 3. Check before filing

Run the same checks as `/write-tests`:
- one behavior; 1-5 unambiguous, unit-testable criteria
- nothing contradicts the Out of scope list or the Behavior
- interface details (node names, functions, measurements) are left for `/write-tests` to
  choose, unless they change what the feature does

If something would change what the feature does and the request doesn't say (e.g. a number,
which side of the screen, what happens in an edge case), **ask me in chat first**: short
numbered questions, each with a suggested default. Don't file until I've answered or said
"use the defaults".

## 4. Show, then file

1. Write each ticket body to `.agent/ticket-<slug>.md`, ending with the line
   `<!-- checked: /new-ticket -->`. It's invisible on GitHub, and tells `/write-tests` the
   ticket already passed these checks with my agreement, so it can skip re-checking.
2. Show me each ticket's title and full text, plus any choices you made that I might want to
   change.
3. File each one, in build order: `bash tools/github.sh create "<title>" .agent/ticket-<slug>.md`
   (this asks for my permission; it adds only the `feature` label).
4. If filing fails (e.g. the token can't write issues), tell me, and tell me to paste the
   `.agent/ticket-<slug>.md` files into **Feature (paste whole ticket)** on GitHub instead.
5. Tell me the new issue numbers and links, and that `/write-tests <N>` is next for the first.
