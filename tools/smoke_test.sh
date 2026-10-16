#!/usr/bin/env bash
# Runs the main scene headless for N frames.
# Fails if Godot exits non-zero, the scene never loads, or any error is logged.
set -uo pipefail

GODOT="${GODOT:-godot}"
FRAMES="${FRAMES:-300}"
cd "$(dirname "$0")/.."
LOG="$(mktemp)"

"$GODOT" --headless --path . --import
# --fixed-fps 60: run the frames back to back instead of in real time (same game time per frame).
"$GODOT" --headless --fixed-fps 60 --path . --quit-after "$FRAMES" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "SMOKE FAIL: Godot exited with code $status"; exit 1
fi
if ! grep -q "SMOKE_MARKER: main scene ready" "$LOG"; then
  echo "SMOKE FAIL: main scene never reported ready"; exit 1
fi
if grep -Eq "SCRIPT ERROR|USER ERROR|^ERROR:" "$LOG"; then
  echo "SMOKE FAIL: errors in log (see output above)"; exit 1
fi
echo "SMOKE PASS: main scene ran $FRAMES frames with no errors"
