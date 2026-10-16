# Eldritch Tactics (Godot 4.7.2)

A 3D isometric game, built ticket by ticket, with tests and a headless smoke run gating every
change.

## Setup

1. Install Godot 4.7.2 (standard build). Point the scripts at it with `GODOT`, e.g. in Git Bash:
   `export GODOT="/c/Users/<you>/Godot/Godot_v4.7.2-stable_win64_console.exe"`.
2. GUT 9.7 is already in `addons/gut/`. To use its editor panel, enable it in
   Project > Project Settings > Plugins.
3. Commit everything Godot generates (including `*.uid` files), but never `.godot/`.

## Checks

```bash
bash tools/run_tests.sh    # unit tests (GUT), exit 0 = pass; pass test files to run just those
bash tools/smoke_test.sh   # runs the main scene headless for 300 frames, fails on errors
```

Both run in GitHub Actions on every push and pull request (`.github/workflows/ci.yml`).
Protect `main` (Settings > Branches): require a pull request and the `godot-checks` status check.

## Tickets

Work is tracked as small Feature issues, each moving through status labels. The AI work runs
locally in Claude Code: `/new-ticket <what you want>` to file tickets, then `/ticket <N>` for one
ticket, or `/tickets <N> <N> ...` to work a list of them in order, as stacked PRs.
See [docs/WORKFLOW.md](docs/WORKFLOW.md).

## Layout

- `scenes/`, `scripts/` - game code
- `tests/unit/` - GUT tests (`test_*.gd`)
- `tools/` - scripts run locally, in CI, and by the AI
- `addons/gut/` - the GUT test framework
